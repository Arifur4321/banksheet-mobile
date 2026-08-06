#!/usr/bin/env python3
"""Did the native configuration actually land?

    python3 tool/native/verify.py

WHY THIS EXISTS
---------------
`android/` and `ios/` are gitignored and regenerated per machine, so after every
clone — and after every `flutter create` — the app's identity has to be
reinstalled by `apply.py`. Skip that step and the build still succeeds: you get
a working app with the Flutter logo for an icon, the Flutter splash screen, no
entry in Android's "open with" list for PDFs, the wrong applicationId, and an
iOS binary that terminates the moment the camera is touched.

Every one of those is invisible until you look at the phone. This script looks
for you, and exits non-zero if anything is missing, so `tool/setup.ps1` and
`tool/setup.sh` can fail loudly instead of printing success over a broken tree.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ANDROID = os.path.join(ROOT, 'android')
IOS = os.path.join(ROOT, 'ios')

PACKAGE = 'pro.banksheet.mobile'
APP_NAME = 'BankSheet Pro'

failures = []
notes = []


def check(condition, message, fix):
    if condition:
        print(f'  ok    {message}')
    else:
        print(f'  FAIL  {message}')
        failures.append((message, fix))


def read(path):
    try:
        with open(path, encoding='utf-8') as f:
            return f.read()
    except OSError:
        return ''


def android_checks():
    print('Android')
    if not os.path.isdir(ANDROID) or not os.listdir(ANDROID):
        print('  FAIL  android/ is empty')
        failures.append((
            'android/ is empty',
            'flutter create . --platforms=android,ios --org pro.banksheet '
            '--project-name banksheet_mobile'))
        return

    res = os.path.join(ANDROID, 'app', 'src', 'main', 'res')

    check(os.path.exists(os.path.join(res, 'mipmap-xxhdpi', 'ic_launcher.png')),
          'launcher icon installed', 'python tool/native/apply.py')
    check(os.path.exists(os.path.join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml')),
          'adaptive icon installed', 'python tool/native/apply.py')
    check(os.path.exists(os.path.join(res, 'drawable', 'launch_background.xml')),
          'launch screen drawable installed', 'python tool/native/apply.py')
    check(os.path.exists(os.path.join(res, 'values-v31', 'styles.xml')),
          'Android 12+ splash configured', 'python tool/native/apply.py')
    check(os.path.exists(os.path.join(res, 'drawable-xxhdpi', 'splash_logo.png')),
          'splash logo installed', 'python tool/native/make_icons.py')

    manifest = read(os.path.join(ANDROID, 'app', 'src', 'main', 'AndroidManifest.xml'))
    check(f'android:label="{APP_NAME}"' in manifest,
          f'app name is "{APP_NAME}"', 'python tool/native/apply.py')
    check('application/pdf' in manifest,
          'PDF "open with" intent filters present', 'python tool/native/apply.py')
    # Asserted ABSENT, not present. Declaring CAMERA while never requesting it
    # at runtime makes MediaStore.ACTION_IMAGE_CAPTURE throw a SecurityException
    # on Android 6+, which is exactly "Scan to PDF does nothing". See the note
    # in apply.py.
    check('android.permission.CAMERA' not in manifest,
          'CAMERA permission absent (required for Scan to PDF)', 'python tool/native/apply.py')

    gradle = read(os.path.join(ANDROID, 'app', 'build.gradle.kts'))
    check(f'applicationId = "{PACKAGE}"' in gradle,
          f'applicationId is {PACKAGE}', 'python tool/native/apply.py')
    check('keystorePropertiesFile' in gradle,
          'release signing config installed', 'python tool/native/apply.py')

    # Informational: signing is only needed for a store build.
    if os.path.exists(os.path.join(ANDROID, 'key.properties')):
        notes.append('android/key.properties found — release builds will be '
                     'signed with your upload key.')
    else:
        notes.append('android/key.properties is absent. `flutter run` and '
                     '`flutter build apk` still work; `flutter build appbundle` '
                     'will produce a DEBUG-signed bundle that Play rejects. '
                     'See android/key.properties.example.')


def ios_checks():
    print('iOS')
    if not os.path.isdir(IOS) or not os.listdir(IOS):
        print('  --    ios/ is empty (fine on Windows; run this on the Mac)')
        return

    plist = read(os.path.join(IOS, 'Runner', 'Info.plist'))
    check(f'<string>{APP_NAME}</string>' in plist,
          f'display name is "{APP_NAME}"', 'python3 tool/native/apply.py')
    check('NSCameraUsageDescription' in plist,
          'camera usage description present (the app CRASHES without it)',
          'python3 tool/native/apply.py')
    check('NSPhotoLibraryUsageDescription' in plist,
          'photo library usage description present',
          'python3 tool/native/apply.py')
    check('com.adobe.pdf' in plist,
          'PDF document type registered', 'python3 tool/native/apply.py')

    icons = os.path.join(IOS, 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    check(os.path.exists(os.path.join(icons, 'Icon-App-60x60@3x.png')),
          'app icon set installed', 'python3 tool/native/apply.py')
    check(os.path.exists(os.path.join(
        IOS, 'Runner', 'Assets.xcassets', 'LaunchImage.imageset', 'Contents.json')),
        'launch image installed', 'python3 tool/native/apply.py')

    pbx = read(os.path.join(IOS, 'Runner.xcodeproj', 'project.pbxproj'))
    ids = {i.strip() for i in
           re.findall(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', pbx)}
    check(any(i == PACKAGE for i in ids),
          f'bundle identifier is {PACKAGE}', 'python3 tool/native/apply.py')

    podfile_path = os.path.join(IOS, 'Podfile')
    if not os.path.exists(podfile_path):
        # CocoaPods writes it during the first iOS build, which only happens on
        # a Mac. Its absence on Windows is not a defect.
        print('  --    Podfile not generated yet (normal off macOS)')
    else:
        check(bool(re.search(r"^platform :ios, '1[5-9]", read(podfile_path), re.M)),
              'Podfile targets iOS 15 or later', 'python3 tool/native/apply.py')


def main():
    android_checks()
    print()
    ios_checks()
    print()

    for note in notes:
        print(f'  note  {note}')
    if notes:
        print()

    if not failures:
        print('Native configuration is complete.')
        return 0

    print(f'{len(failures)} problem(s). Fix with:\n')
    # dict.fromkeys keeps the first-seen order and drops duplicates, so the
    # same command is not printed six times.
    for fix in dict.fromkeys(fix for _, fix in failures):
        print(f'    {fix}')
    print('\nOn a fresh checkout, run all of it:  tool/setup.ps1  (or tool/setup.sh)')
    return 1


if __name__ == '__main__':
    sys.exit(main())
