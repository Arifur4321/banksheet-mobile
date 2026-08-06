#!/usr/bin/env python3
"""Install BankSheet Pro's native configuration into the generated platform trees.

    python3 tool/native/apply.py

WHY THIS EXISTS
---------------
`.gitignore` excludes /android/ and /ios/ — they are regenerated per machine
with `flutter create .`. That is fine for scaffolding and useless for anything
we actually care about: the launcher icon, the display name, and the intent
filters that make BankSheet Pro appear in Android's "open with" list for a PDF.
Those would be lost on every regeneration.

So the customisation lives here, in tracked files, and this script installs it.
Run it after `flutter create`, after cloning, or any time the Android chooser
stops offering the app. It is idempotent — running it twice changes nothing.

WHAT IT DOES
------------
Android
  * launcher icons at every density, plus the adaptive icon (foreground layer
    and a background colour)
  * the LAUNCH SCREEN: a branded window background for Android 11 and below,
    and the Android 12+ splash-screen API above it, so the moment between
    tapping the icon and Flutter's first frame is brand green with the PDF mark
    on it rather than the stock white Flutter screen
  * android:label -> "BankSheet Pro"
  * VIEW intent filters for application/pdf over content:// and file://, which
    is what puts the app in the chooser
  * SEND intent filter, so "Share -> BankSheet Pro" works too
  * MainActivity.kt that resolves the incoming URI to a real readable file and
    hands the path to Dart over a MethodChannel

iOS
  * AppIcon set at every size, alpha stripped (an icon with an alpha channel is
    rejected at upload)
  * LaunchScreen.storyboard + a LaunchImage set — the iOS half of the same
    launch-screen job
  * CFBundleDisplayName -> "BankSheet Pro"
  * a PDF document type + LSSupportsOpeningDocumentsInPlace, the equivalent of
    the Android intent filter
"""

import json
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ICONS = os.path.join(ROOT, 'tool', 'native', 'icons')

APP_NAME = 'BankSheet Pro'

# The store identity. It must match, exactly and everywhere:
#   * MOBILE_GOOGLE_PACKAGE_NAME and MOBILE_APPLE_BUNDLE_ID in the VPS .env
#   * the package/bundle id registered in Play Console and App Store Connect
#   * the `aud` of the Play Pub/Sub push subscription
# `flutter create --org pro.banksheet --project-name banksheet_mobile` produces
# `pro.banksheet.banksheet_mobile` instead, which is why this script overwrites
# it. Getting this wrong does not fail the build — it fails receipt validation
# in production, which is a much worse place to find out.
PACKAGE = 'pro.banksheet.mobile'

# The Kotlin source package, which is NOT the same thing. It is the Java
# namespace MainActivity.kt lives in, and `flutter create` derives it from the
# project name. Left alone deliberately: renaming it would move the source file
# for no benefit, and Android has allowed namespace != applicationId for years.
KOTLIN_PKG = 'pro.banksheet.banksheet_mobile'

CHANNEL = 'pro.banksheet/incoming_file'
ADAPTIVE_BG = '#102820'   # AppColors.forest

# Android API levels.
#   minSdk 24 — Android 7.0. Pdfium (via pdfx), Play Billing 6 and the system
#               photo picker fallback all want 21+; 24 is where the toolchain
#               stops needing multidex workarounds. Covers ~97% of active
#               devices. Lower it if you have a reason and re-test the reader.
#   targetSdk 36 — mandatory for new Play submissions from 31 August 2026.
MIN_SDK = 24
TARGET_SDK = 36
COMPILE_SDK = 36

# The launch screen's colour. Same value as ADAPTIVE_BG and as the top-left of
# the icon's gradient, so the icon appears to expand into the launch screen
# instead of cutting to a different green.
SPLASH_BG = '#102820'     # AppColors.forest

ok, warn = [], []


def _say(bucket, msg):
    bucket.append(msg)
    print(('  ok  ' if bucket is ok else '  !!  ') + msg)


def _write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(content)


# ---------------------------------------------------------------- android ---

def android(base):
    res = os.path.join(base, 'app', 'src', 'main', 'res')

    # 1. icons
    for density in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'):
        dst = os.path.join(res, f'mipmap-{density}')
        os.makedirs(dst, exist_ok=True)
        for stem in ('ic_launcher', 'ic_launcher_foreground'):
            src = os.path.join(ICONS, f'android_{density}_{stem}.png')
            if os.path.exists(src):
                shutil.copyfile(src, os.path.join(dst, f'{stem}.png'))
    _say(ok, 'launcher icons installed at 5 densities')

    # 2. adaptive icon
    _write(os.path.join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml'),
           '<?xml version="1.0" encoding="utf-8"?>\n'
           '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@color/ic_launcher_background" />\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
           '    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />\n'
           '</adaptive-icon>\n')
    _write(os.path.join(res, 'values', 'ic_launcher_background.xml'),
           '<?xml version="1.0" encoding="utf-8"?>\n'
           '<resources>\n'
           f'    <color name="ic_launcher_background">{ADAPTIVE_BG}</color>\n'
           '</resources>\n')
    _say(ok, 'adaptive icon written (foreground + background + monochrome)')

    # 2b. launch screen
    android_launch_screen(res)

    # 3. manifest
    manifest = os.path.join(base, 'app', 'src', 'main', 'AndroidManifest.xml')
    if not os.path.exists(manifest):
        _say(warn, 'AndroidManifest.xml missing — run `flutter create .` first')
        return
    s = open(manifest, encoding='utf-8').read()

    s2 = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', s, count=1)
    if s2 != s:
        _say(ok, f'android:label -> "{APP_NAME}"')
    s = s2

    if 'android.permission.INTERNET' not in s:
        s = s.replace('<application',
                      '    <uses-permission android:name="android.permission.INTERNET" />\n'
                      '    <uses-permission android:name="com.android.vending.BILLING" />\n'
                      '\n    <application', 1)
        _say(ok, 'permissions added (INTERNET, BILLING)')

    # android.permission.CAMERA is deliberately NOT declared, and an older
    # manifest that declares it is repaired here.
    #
    # This is the bug that broke Scan to PDF on every Android 6+ device. The
    # scanner does not open a camera: it sends MediaStore.ACTION_IMAGE_CAPTURE
    # through image_picker and lets the system camera app take the photo. That
    # needs no permission at all -- UNLESS the manifest declares CAMERA, and
    # then Android's contract is explicit:
    #
    #   "if your app targets M and above and declares as using the CAMERA
    #    permission which is not granted, then attempting to use this action
    #    will result in a SecurityException."
    #    -- developer.android.com, MediaStore.ACTION_IMAGE_CAPTURE
    #
    # Nothing in this app requests CAMERA at runtime (there is no
    # permission_handler dependency, and image_picker deliberately does not ask
    # for a permission it does not need), so the declaration alone guaranteed
    # the capture intent would be refused. Declaring it and requesting it would
    # also cost the app a permission prompt and a Play listing disclosure for a
    # capability it never uses.
    if 'android.permission.CAMERA' in s:
        s = re.sub(
            r'[ \t]*<uses-permission android:name="android\.permission\.CAMERA"[^>]*/>\s*\n',
            '',
            s,
        )
        _say(ok, 'CAMERA permission removed (it makes ACTION_IMAGE_CAPTURE throw)')

    if 'application/pdf' not in s:
        # Anchored on the LAUNCHER filter's closing tag, which every
        # Flutter-generated manifest has exactly once.
        #
        # Three VIEW filters, not one, because "which app can open this PDF" is
        # decided by whatever the *sending* app puts in the intent, and file
        # managers disagree wildly:
        #
        #   1. mimeType application/pdf — the correct case, and what a
        #      well-behaved file manager or mail client sends.
        #   2. mimeType application/octet-stream or */* with a .pdf path — what
        #      a great many Android file managers actually send, because they
        #      never resolved the type. Without this filter the app is simply
        #      absent from their chooser, which is exactly the symptom of
        #      "I don't see BankSheet Pro in the list".
        #   3. http/https links ending in .pdf — a PDF tapped in a browser.
        #
        # Path patterns need the doubled-escape form: in an intent filter, `\\.`
        # is a literal dot and `.*` is any run of characters, and Android also
        # requires the leading `.*` to be repeated to match a path with a dot
        # earlier in it. This is the documented incantation, not a typo.
        anchor = '</intent-filter>'
        filters = (
            '</intent-filter>\n\n'
            '                <!-- 1. A properly typed PDF. -->\n'
            '                <intent-filter android:label="@string/app_name">\n'
            '                    <action android:name="android.intent.action.VIEW" />\n'
            '                    <category android:name="android.intent.category.DEFAULT" />\n'
            '                    <category android:name="android.intent.category.BROWSABLE" />\n'
            '                    <data android:scheme="content" android:mimeType="application/pdf" />\n'
            '                    <data android:scheme="file" android:mimeType="application/pdf" />\n'
            '                </intent-filter>\n\n'
            '                <!-- 2. A file manager that did not resolve the type.\n'
            '                     Matched on the extension instead. -->\n'
            '                <intent-filter android:label="@string/app_name">\n'
            '                    <action android:name="android.intent.action.VIEW" />\n'
            '                    <category android:name="android.intent.category.DEFAULT" />\n'
            '                    <category android:name="android.intent.category.BROWSABLE" />\n'
            '                    <data android:scheme="content" />\n'
            '                    <data android:scheme="file" />\n'
            '                    <data android:host="*" />\n'
            '                    <data android:mimeType="application/octet-stream" />\n'
            '                    <data android:pathPattern=".*\\\\.pdf" />\n'
            '                    <data android:pathPattern=".*\\\\..*\\\\.pdf" />\n'
            '                    <data android:pathPattern=".*\\\\..*\\\\..*\\\\.pdf" />\n'
            '                </intent-filter>\n\n'
            '                <!-- 3. A PDF link tapped in a browser. -->\n'
            '                <intent-filter android:label="@string/app_name">\n'
            '                    <action android:name="android.intent.action.VIEW" />\n'
            '                    <category android:name="android.intent.category.DEFAULT" />\n'
            '                    <category android:name="android.intent.category.BROWSABLE" />\n'
            '                    <data android:scheme="http" android:host="*" android:pathPattern=".*\\\\.pdf" />\n'
            '                    <data android:scheme="https" android:host="*" android:pathPattern=".*\\\\.pdf" />\n'
            '                </intent-filter>\n\n'
            '                <!-- "Share -> BankSheet Pro" from any app. -->\n'
            '                <intent-filter android:label="@string/app_name">\n'
            '                    <action android:name="android.intent.action.SEND" />\n'
            '                    <category android:name="android.intent.category.DEFAULT" />\n'
            '                    <data android:mimeType="application/pdf" />\n'
            '                </intent-filter>\n'
        )
        s = s.replace(anchor, filters, 1)
        _say(ok, 'PDF VIEW (typed, extension, web) + SEND intent filters added')

    _write(manifest, s)

    _write(os.path.join(res, 'values', 'strings.xml'),
           '<?xml version="1.0" encoding="utf-8"?>\n'
           '<resources>\n'
           f'    <string name="app_name">{APP_NAME}</string>\n'
           '</resources>\n')

    # 4. MainActivity — resolve the incoming URI to something Dart can open
    kt_dir = os.path.join(base, 'app', 'src', 'main', 'kotlin', *KOTLIN_PKG.split('.'))
    _write(os.path.join(kt_dir, 'MainActivity.kt'), MAIN_ACTIVITY)
    _say(ok, 'MainActivity.kt written (content:// -> cache file bridge)')

    # 5. store identity, API levels and release signing
    android_gradle(base)


GRADLE_SIGNING = '''
// ---------------------------------------------------------------------------
// Release signing, installed by tool/native/apply.py.
//
// The key itself is never in git. Create android/key.properties from
// android/key.properties.example on the machine that produces store builds:
//
//     storePassword=...
//     keyPassword=...
//     keyAlias=upload
//     storeFile=app/upload-keystore.jks
//
// and generate the keystore once with:
//
//     keytool -genkey -v -keystore android/app/upload-keystore.jks \\
//             -keyalg RSA -keysize 2048 -validity 10000 -alias upload
//
// When key.properties is absent the release build falls back to the debug key,
// so `flutter run` and `flutter build apk` still work for a developer with no
// key. Play will refuse a debug-signed bundle, which is the correct outcome: a
// build that cannot be uploaded beats one that uploads under the wrong
// identity and can never be updated.
//
// The file is parsed by hand rather than with java.util.Properties, and that
// is not a preference. Inside a Gradle Kotlin build script `java` resolves to
// the Java plugin's extension, not to the JDK package, so `java.util.Properties`
// fails to compile with "Unresolved reference: util". An `import` at the top of
// the file would fix it, but this script patches build.gradle.kts in place and
// cannot reliably insert one above the `plugins {}` block. Six lines of Kotlin
// stdlib have no such problem.
// ---------------------------------------------------------------------------
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties: Map<String, String> =
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.readLines()
            .map { it.trim() }
            .filter { it.contains("=") && !it.startsWith("#") }
            .associate {
                val i = it.indexOf("=")
                it.substring(0, i).trim() to it.substring(i + 1).trim()
            }
    } else {
        emptyMap()
    }

'''

GRADLE_SIGNING_CONFIGS = '''    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"]
                keyPassword = keystoreProperties["keyPassword"]
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"]
            }
        }
    }

'''

# The first release of this script emitted `java.util.Properties()`, which does
# not compile in a Gradle Kotlin script. Anyone who ran that version has a
# broken build.gradle.kts, and the "already present" guard below would happily
# leave it broken. These two replacements upgrade it in place.
GRADLE_BROKEN_PROPS = '''val keystoreProperties = java.util.Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}'''

GRADLE_FIXED_PROPS = '''val keystoreProperties: Map<String, String> =
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.readLines()
            .map { it.trim() }
            .filter { it.contains("=") && !it.startsWith("#") }
            .associate {
                val i = it.indexOf("=")
                it.substring(0, i).trim() to it.substring(i + 1).trim()
            }
    } else {
        emptyMap()
    }'''

KEY_PROPERTIES_EXAMPLE = '''# Copy to android/key.properties and fill in. NEVER commit the real file —
# .gitignore already excludes android/key.properties and *.jks.
#
# Generate the keystore once, and back it up somewhere you will still have in
# five years: losing it means you can never update the app on Play under the
# same listing.
#
#   keytool -genkey -v -keystore android/app/upload-keystore.jks \\
#           -keyalg RSA -keysize 2048 -validity 10000 -alias upload
#
storePassword=
keyPassword=
keyAlias=upload
storeFile=app/upload-keystore.jks
'''


def android_gradle(base):
    """Store identity, API levels and release signing in app/build.gradle.kts.

    `flutter create` writes an applicationId derived from the project name, no
    release signing config, and whatever minSdk the current Flutter happens to
    default to. All three are wrong for this app, and all three are silently
    wrong: the build succeeds and the problem appears at upload time, or worse,
    in production when Play receipt validation starts rejecting purchases
    because the package name it was told about does not exist.
    """
    gradle = os.path.join(base, 'app', 'build.gradle.kts')
    if not os.path.exists(gradle):
        # Groovy-DSL projects predate this script; nothing here is worth
        # guessing at against a file shape it was not written for.
        if os.path.exists(os.path.join(base, 'app', 'build.gradle')):
            _say(warn, 'app/build.gradle is Groovy DSL — set applicationId, '
                       f'minSdk {MIN_SDK}, targetSdk {TARGET_SDK} and the '
                       'release signingConfig by hand (README section 9)')
        else:
            _say(warn, 'app/build.gradle.kts missing — run `flutter create .` first')
        return

    s = open(gradle, encoding='utf-8').read()
    original = s

    s2 = re.sub(r'applicationId\s*=\s*"[^"]*"',
                f'applicationId = "{PACKAGE}"', s, count=1)
    if s2 != s:
        _say(ok, f'applicationId -> {PACKAGE}')
    s = s2

    # `flutter.minSdkVersion` and friends are Flutter's indirections; replacing
    # them with literals is what pins the app to a level the stores accept
    # regardless of which Flutter the next machine has installed.
    for key, value in (('minSdk', MIN_SDK),
                       ('targetSdk', TARGET_SDK),
                       ('compileSdk', COMPILE_SDK)):
        s = re.sub(rf'{key}\s*=\s*[^\n]+', f'{key} = {value}', s, count=1)
    _say(ok, f'minSdk {MIN_SDK}, targetSdk {TARGET_SDK}, compileSdk {COMPILE_SDK}')

    # Repair a tree patched by the first, broken release of this script before
    # deciding whether anything needs installing.
    if GRADLE_BROKEN_PROPS in s:
        s = s.replace(GRADLE_BROKEN_PROPS, GRADLE_FIXED_PROPS, 1)
        s = s.replace('keystoreProperties.getProperty("keyAlias")',
                      'keystoreProperties["keyAlias"]')
        s = s.replace('keystoreProperties.getProperty("keyPassword")',
                      'keystoreProperties["keyPassword"]')
        s = s.replace('file(keystoreProperties.getProperty("storeFile"))',
                      'keystoreProperties["storeFile"]?.let { file(it) }')
        s = s.replace('keystoreProperties.getProperty("storePassword")',
                      'keystoreProperties["storePassword"]')
        _say(ok, 'repaired the java.util.Properties signing block '
                 '(it does not compile in a Gradle Kotlin script)')

    if 'keystorePropertiesFile' not in s:
        # Ahead of the `android {` block: the properties are read at
        # configuration time and referenced from inside it.
        s = re.sub(r'\nandroid\s*\{', GRADLE_SIGNING + 'android {', s, count=1)

        # signingConfigs must be declared before buildTypes references it.
        s = re.sub(r'(\n)(\s*)buildTypes\s*\{',
                   '\n' + GRADLE_SIGNING_CONFIGS + r'\2buildTypes {', s, count=1)

        s = re.sub(
            r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
            'signingConfig = if (keystorePropertiesFile.exists()) {\n'
            '                signingConfigs.getByName("release")\n'
            '            } else {\n'
            '                // No key on this machine — still builds, but Play\n'
            '                // will reject the bundle. That is deliberate.\n'
            '                signingConfigs.getByName("debug")\n'
            '            }',
            s, count=1)
        _say(ok, 'release signing config installed (reads android/key.properties)')
    else:
        _say(ok, 'release signing config already present')

    if s != original:
        _write(gradle, s)

    example = os.path.join(base, 'key.properties.example')
    if not os.path.exists(example):
        _write(example, KEY_PROPERTIES_EXAMPLE)


def android_launch_screen(res):
    """The branded launch screen, on both sides of the Android 12 divide.

    Two different mechanisms, and shipping only one of them is why an app looks
    right on the maintainer's phone and wrong on the tester's:

    **Android 11 and below** draw `android:windowBackground` from the activity's
    theme while the process starts. Flutter's generated `launch_background.xml`
    is a plain white colour, which is the stock screen this replaces.

    **Android 12 and above (API 31+)** ignore that entirely and run the platform
    splash-screen API instead. It is not optional and it cannot be turned off:
    if you do not configure it you get the launcher icon on the system window
    background, which on most devices is white. So `values-v31/styles.xml`
    below sets the brand colour and a purpose-built icon asset.

    A note on the v31 icon: the platform masks it to a circle and only the inner
    two thirds survive, which is why `make_icons.py` draws a small glyph on a
    large transparent canvas for that one file rather than reusing the launcher
    icon.
    """
    # 1. the logo bitmaps, one per density
    installed = 0
    for density in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'):
        src = os.path.join(ICONS, f'android_{density}_splash_logo.png')
        if not os.path.exists(src):
            continue
        dst = os.path.join(res, f'drawable-{density}')
        os.makedirs(dst, exist_ok=True)
        shutil.copyfile(src, os.path.join(dst, 'splash_logo.png'))
        installed += 1

    v31_src = os.path.join(ICONS, 'android_splash_icon_v31.png')
    if os.path.exists(v31_src):
        dst = os.path.join(res, 'drawable-nodpi')
        os.makedirs(dst, exist_ok=True)
        shutil.copyfile(v31_src, os.path.join(dst, 'splash_icon.png'))

    if installed == 0:
        _say(warn, 'splash logos missing — run `python3 tool/native/make_icons.py`')
        return

    # 2. colours. Kept in their own file rather than appended to an existing
    #    one, so re-running this script cannot duplicate a resource name.
    _write(os.path.join(res, 'values', 'splash_colors.xml'),
           '<?xml version="1.0" encoding="utf-8"?>\n'
           '<resources>\n'
           f'    <color name="brand_splash">{SPLASH_BG}</color>\n'
           '</resources>\n')

    # 3. the pre-12 window background, light and dark. Both are the dark brand
    #    green: this screen is a brand moment, not a surface that follows the
    #    system theme, and a white flash before a dark app is the exact jolt
    #    the launch screen exists to remove.
    layer = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- Drawn by the window manager before Flutter has an engine. Keep it\n'
        '     to a colour and one bitmap: anything that needs inflating costs\n'
        '     time on precisely the low-end devices this is meant to help. -->\n'
        '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <item android:drawable="@color/brand_splash" />\n'
        '    <item>\n'
        '        <bitmap\n'
        '            android:gravity="center"\n'
        '            android:src="@drawable/splash_logo" />\n'
        '    </item>\n'
        '</layer-list>\n'
    )
    for folder in ('drawable', 'drawable-v21', 'drawable-night', 'drawable-night-v21'):
        _write(os.path.join(res, folder, 'launch_background.xml'), layer)

    # 4. themes. LaunchTheme is what the activity wears until Flutter swaps it
    #    for NormalTheme; both are declared here so a `flutter create` that
    #    wrote a white default is fully overwritten rather than half-patched.
    styles = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <!-- Shown from the moment the icon is tapped until Flutter renders\n'
        '         its first frame. `windowFullscreen=false` matters: a launch\n'
        '         screen that hides the status bar makes the bar appear a beat\n'
        '         later, and the whole page jumps. -->\n'
        '    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">\n'
        '        <item name="android:windowBackground">@drawable/launch_background</item>\n'
        '        <item name="android:windowFullscreen">false</item>\n'
        f'        <item name="android:statusBarColor">{SPLASH_BG}</item>\n'
        f'        <item name="android:navigationBarColor">{SPLASH_BG}</item>\n'
        '        <item name="android:windowLightStatusBar">false</item>\n'
        '    </style>\n'
        '\n'
        '    <!-- Applied the instant the first frame is up. Flutter paints its\n'
        '         own background from here on; this colour only shows during a\n'
        '         route transition. -->\n'
        '    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">\n'
        '        <item name="android:windowBackground">?android:colorBackground</item>\n'
        '    </style>\n'
        '</resources>\n'
    )
    _write(os.path.join(res, 'values', 'styles.xml'), styles)
    _write(os.path.join(res, 'values-night', 'styles.xml'), styles)

    # 5. Android 12+. `windowSplashScreenAnimatedIcon` accepts a static drawable
    #    as well as an AnimatedVectorDrawable; a still mark that hands over to
    #    the app's own animation reads better than two animations back to back.
    _write(os.path.join(res, 'values-v31', 'styles.xml'),
           '<?xml version="1.0" encoding="utf-8"?>\n'
           '<resources>\n'
           '    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">\n'
           '        <item name="android:windowSplashScreenBackground">'
           '@color/brand_splash</item>\n'
           '        <item name="android:windowSplashScreenAnimatedIcon">'
           '@drawable/splash_icon</item>\n'
           '        <item name="android:windowSplashScreenIconBackgroundColor">'
           '@color/brand_splash</item>\n'
           '        <item name="android:windowLayoutInDisplayCutoutMode">'
           'shortEdges</item>\n'
           '        <!-- Still consumed on 12+ for the window behind the splash. -->\n'
           '        <item name="android:windowBackground">@drawable/launch_background</item>\n'
           '        <item name="android:windowFullscreen">false</item>\n'
           '    </style>\n'
           '\n'
           '    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">\n'
           '        <item name="android:windowBackground">?android:colorBackground</item>\n'
           '    </style>\n'
           '</resources>\n')

    _say(ok, f'launch screen installed ({installed} densities + Android 12 splash API)')


MAIN_ACTIVITY = '''package ''' + KOTLIN_PKG + '''

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Receives PDFs opened or shared from other apps.
 *
 * The hard part is not the intent filter, it is the URI. Another app hands us a
 * `content://` URI backed by its own provider: it has no filesystem path, the
 * permission to read it is scoped to this Activity, and it can be revoked the
 * moment we return. pdfx needs a real file. So the bytes are copied once into
 * our own cache and Dart is given that path.
 *
 * Copying is the right call rather than a workaround. The alternative is
 * holding a borrowed file descriptor across a Flutter route transition, which
 * fails intermittently on exactly the devices you cannot reproduce on.
 *
 * Two arrival paths, both handled:
 *   cold start  -> the intent is on the Activity when Dart first asks
 *   already open -> onNewIntent fires (launchMode is singleTop)
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var pending: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "''' + CHANNEL + '''"
        ).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    // Dart asks once at startup. Consuming the value here means
                    // a hot restart does not reopen the same document forever.
                    "consumePending" -> {
                        val path = pending ?: resolve(intent)
                        pending = null
                        result.success(path)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val path = resolve(intent)
        if (path != null) {
            // The engine may not be attached yet on a very fast second launch,
            // so hold it rather than dropping it on the floor.
            if (channel != null) channel!!.invokeMethod("openFile", path) else pending = path
        }
    }

    private fun resolve(intent: Intent?): String? {
        if (intent == null) return null
        val uri: Uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        } ?: return null

        return try {
            val name = displayName(uri) ?: "document.pdf"
            // One inbox directory, cleared each time, so a user who opens forty
            // PDFs does not end up with forty copies in their app storage.
            val dir = File(cacheDir, "incoming").apply {
                deleteRecursively()
                mkdirs()
            }
            val out = File(dir, name)
            contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { input.copyTo(it) }
            } ?: return null
            out.absolutePath
        } catch (e: Exception) {
            // A failed copy must not crash the launch. Dart shows its own
            // "this PDF could not be opened" state when the path never arrives.
            null
        }
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        return contentResolver.query(uri, null, null, null, null)?.use { c ->
            val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (i >= 0 && c.moveToFirst()) c.getString(i) else null
        }
    }
}
'''


# -------------------------------------------------------------------- ios ---

IOS_SET = [
    ('20', 1, '20x20', 'iphone'), ('40', 2, '20x20', 'iphone'), ('60', 3, '20x20', 'iphone'),
    ('29', 1, '29x29', 'iphone'), ('58', 2, '29x29', 'iphone'), ('87', 3, '29x29', 'iphone'),
    ('40', 1, '40x40', 'iphone'), ('80', 2, '40x40', 'iphone'), ('120', 3, '40x40', 'iphone'),
    ('120', 2, '60x60', 'iphone'), ('180', 3, '60x60', 'iphone'),
    ('20', 1, '20x20', 'ipad'), ('40', 2, '20x20', 'ipad'),
    ('29', 1, '29x29', 'ipad'), ('58', 2, '29x29', 'ipad'),
    ('40', 1, '40x40', 'ipad'), ('80', 2, '40x40', 'ipad'),
    ('76', 1, '76x76', 'ipad'), ('152', 2, '76x76', 'ipad'),
    ('167', 2, '83.5x83.5', 'ipad'),
    ('1024', 1, '1024x1024', 'ios-marketing'),
]


def ios(base):
    appicon = os.path.join(base, 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    if not os.path.isdir(os.path.dirname(appicon)):
        _say(warn, 'ios/Runner/Assets.xcassets missing — skipping iOS')
        return
    os.makedirs(appicon, exist_ok=True)

    images = []
    for px, scale, size, idiom in IOS_SET:
        src = os.path.join(ICONS, f'ios_{px}.png')
        if not os.path.exists(src):
            continue
        fname = f'Icon-App-{size}@{scale}x.png'
        shutil.copyfile(src, os.path.join(appicon, fname))
        images.append({'size': size, 'idiom': idiom, 'filename': fname, 'scale': f'{scale}x'})

    _write(os.path.join(appicon, 'Contents.json'), json.dumps(
        {'images': images, 'info': {'version': 1, 'author': 'xcode'}}, indent=2) + '\n')
    _say(ok, f'iOS AppIcon set written ({len(images)} entries)')

    ios_launch_screen(base)

    plist = os.path.join(base, 'Runner', 'Info.plist')
    if not os.path.exists(plist):
        _say(warn, 'Info.plist missing — skipping iOS name and document type')
        return
    s = open(plist, encoding='utf-8').read()

    if '<key>CFBundleDisplayName</key>' in s:
        s = re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)',
                   r'\g<1>' + APP_NAME + r'\g<2>', s, count=1)
    else:
        s = s.replace('<dict>',
                      f'<dict>\n\t<key>CFBundleDisplayName</key>\n\t<string>{APP_NAME}</string>', 1)
    _say(ok, f'CFBundleDisplayName -> "{APP_NAME}"')

    # Usage descriptions. iOS does not warn about a missing one — it kills the
    # app the instant the API is touched, with a crash log naming the key. The
    # scanner opens the camera on its very first screen, so without
    # NSCameraUsageDescription the headline feature terminates the process on
    # first tap, on a reviewer's device.
    for key, value in (
        ('NSCameraUsageDescription',
         'BankSheet Pro uses the camera to photograph document pages and turn '
         'them into a PDF.'),
        ('NSPhotoLibraryUsageDescription',
         'BankSheet Pro turns photos you choose into PDF pages.'),
        ('NSPhotoLibraryAddUsageDescription',
         'BankSheet Pro can save a PDF you created back to your device.'),
    ):
        if f'<key>{key}</key>' not in s:
            s = s.replace(
                '</dict>\n</plist>',
                f'\t<key>{key}</key>\n\t<string>{value}</string>\n</dict>\n</plist>',
                1)
    _say(ok, 'camera and photo-library usage descriptions present')

    # Declaring this is what skips the export-compliance questionnaire on every
    # single upload. The app uses HTTPS and nothing else, so it is accurate.
    if 'ITSAppUsesNonExemptEncryption' not in s:
        s = s.replace(
            '</dict>\n</plist>',
            '\t<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>\n</dict>\n</plist>',
            1)

    if 'CFBundleDocumentTypes' not in s:
        doc = (
            '\t<key>CFBundleDocumentTypes</key>\n'
            '\t<array>\n'
            '\t\t<dict>\n'
            '\t\t\t<key>CFBundleTypeName</key>\n'
            '\t\t\t<string>PDF Document</string>\n'
            '\t\t\t<key>LSHandlerRank</key>\n'
            '\t\t\t<string>Alternate</string>\n'
            '\t\t\t<key>LSItemContentTypes</key>\n'
            '\t\t\t<array>\n\t\t\t\t<string>com.adobe.pdf</string>\n\t\t\t</array>\n'
            '\t\t</dict>\n'
            '\t</array>\n'
            '\t<key>LSSupportsOpeningDocumentsInPlace</key>\n'
            '\t<false/>\n'
            '\t<key>UIFileSharingEnabled</key>\n'
            '\t<true/>\n'
        )
        s = s.replace('</dict>\n</plist>', doc + '</dict>\n</plist>', 1)
        _say(ok, 'PDF document type registered')

    _write(plist, s)

    ios_bundle_id(base)
    ios_podfile(base)


def ios_bundle_id(base):
    """PRODUCT_BUNDLE_IDENTIFIER -> the store identity, in every configuration.

    `flutter create --org pro.banksheet` writes `pro.banksheet.banksheetMobile`
    — camel-cased, and not what App Store Connect knows this app as. The value
    appears once per build configuration plus once per test target, so this
    replaces the base string rather than matching each line, which also fixes
    `<base>.RunnerTests` for free.
    """
    pbx = os.path.join(base, 'Runner.xcodeproj', 'project.pbxproj')
    if not os.path.exists(pbx):
        _say(warn, 'Runner.xcodeproj missing — skipping bundle identifier')
        return

    s = open(pbx, encoding='utf-8').read()
    ids = {i.strip() for i in
           re.findall(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', s)}
    bases = {i for i in ids
             if not i.endswith(('.RunnerTests', '.RunnerUITests')) and '$' not in i}

    if bases == {PACKAGE}:
        _say(ok, f'bundle identifier already {PACKAGE}')
        return
    if not bases:
        _say(warn, 'bundle identifier is a build variable — set it in Xcode')
        return

    for old in sorted(bases):
        if old != PACKAGE:
            s = s.replace(old, PACKAGE)

    _write(pbx, s)
    _say(ok, f'bundle identifier -> {PACKAGE}')


def ios_podfile(base):
    """The deployment-target floor.

    StoreKit 2 — which `in_app_purchase` uses on iOS — needs 15.0, and pdfx
    leans on PDFKit APIs that assume it. Flutter's generated Podfile leaves the
    platform line commented out, which resolves to whatever the installed
    CocoaPods defaults to; on a machine with an older default `pod install`
    succeeds and the StoreKit calls fail at runtime instead.
    """
    podfile = os.path.join(base, 'Podfile')
    if not os.path.exists(podfile):
        # Expected on Windows and Linux: the Podfile is generated by CocoaPods
        # during the first iOS build, which only happens on a Mac. Reporting it
        # as a warning there taught the reader to ignore warnings, which is the
        # opposite of what this script's output is for.
        if sys.platform == 'darwin':
            _say(warn, 'Podfile missing — run `cd ios && pod install`, '
                       "then re-run this script to set the platform to 15.0")
        else:
            print('  --   Podfile not generated on this OS; run this script '
                  'again on the Mac before the first iOS build')
        return

    s = open(podfile, encoding='utf-8').read()
    if re.search(r"^platform :ios, '15\.0'", s, re.M):
        _say(ok, 'Podfile already targets iOS 15.0')
        return

    s2 = re.sub(r'^#?\s*platform :ios,.*$', "platform :ios, '15.0'", s,
                count=1, flags=re.M)
    if s2 == s:
        s2 = "platform :ios, '15.0'\n" + s
    _write(podfile, s2)
    _say(ok, 'Podfile platform -> iOS 15.0 (StoreKit 2)')


LAUNCH_STORYBOARD = '''<?xml version="1.0" encoding="UTF-8"?>
<!--
  BankSheet Pro launch screen.

  iOS renders this before the app has run a line of code, so it is a storyboard
  and not a view: nothing here can be computed. The background colour is the
  literal sRGB of AppColors.forest (#102820) because a storyboard cannot read a
  colour from anywhere else, and the image is centred with fixed 120pt sides so
  it lands identically from an SE to a Pro Max.

  Keep this in sync with SPLASH_BG in tool/native/apply.py.
-->
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="22505" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="01J-lp-oVM">
    <dependencies>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="22504"/>
        <capability name="Safe area layout guides" minToolsVersion="9.0"/>
    </dependencies>
    <scenes>
        <scene sceneID="EHf-IW-A2E">
            <objects>
                <viewController id="01J-lp-oVM" sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">
                        <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <subviews>
                            <imageView clipsSubviews="YES" userInteractionEnabled="NO" contentMode="scaleAspectFit" horizontalHuggingPriority="251" verticalHuggingPriority="251" image="LaunchImage" translatesAutoresizingMaskIntoConstraints="NO" id="YRO-k0-Ey4">
                                <rect key="frame" x="136.5" y="366" width="120" height="120"/>
                            </imageView>
                        </subviews>
                        <viewLayoutGuide key="safeArea" id="Bcu-3y-fUS"/>
                        <color key="backgroundColor" red="0.062745098" green="0.156862745" blue="0.125490196" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
                        <constraints>
                            <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerX" secondItem="Ze5-6b-2t3" secondAttribute="centerX" id="cX0-00-001"/>
                            <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerY" secondItem="Ze5-6b-2t3" secondAttribute="centerY" id="cY0-00-002"/>
                            <constraint firstAttribute="width" secondItem="YRO-k0-Ey4" secondAttribute="width" id="wW0-00-003" constant="0.0"/>
                        </constraints>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="iYj-Kq-Ea1" userLabel="First Responder" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="53" y="375"/>
        </scene>
    </scenes>
    <resources>
        <image name="LaunchImage" width="120" height="120"/>
    </resources>
</document>
'''


def ios_launch_screen(base):
    """LaunchScreen.storyboard plus the image set it references.

    `flutter create` writes a storyboard containing a white background and the
    Flutter logo. Replacing it is the iOS half of the Android work above — same
    green, same mark, so the two platforms launch identically.
    """
    imageset = os.path.join(
        base, 'Runner', 'Assets.xcassets', 'LaunchImage.imageset')
    if not os.path.isdir(os.path.dirname(imageset)):
        _say(warn, 'ios/Runner/Assets.xcassets missing — skipping launch screen')
        return

    os.makedirs(imageset, exist_ok=True)
    images = []
    for scale in (1, 2, 3):
        src = os.path.join(ICONS, f'ios_launch_{scale}x.png')
        if not os.path.exists(src):
            continue
        fname = f'LaunchImage{"" if scale == 1 else f"@{scale}x"}.png'
        shutil.copyfile(src, os.path.join(imageset, fname))
        images.append({'idiom': 'universal', 'filename': fname, 'scale': f'{scale}x'})

    if not images:
        _say(warn, 'iOS launch images missing — run `python3 tool/native/make_icons.py`')
        return

    _write(os.path.join(imageset, 'Contents.json'), json.dumps(
        {'images': images, 'info': {'version': 1, 'author': 'xcode'}}, indent=2) + '\n')

    storyboard = os.path.join(
        base, 'Runner', 'Base.lproj', 'LaunchScreen.storyboard')
    _write(storyboard, LAUNCH_STORYBOARD)
    _say(ok, f'iOS launch screen written ({len(images)} scales + storyboard)')


def main():
    if not os.path.isdir(ICONS) or not os.listdir(ICONS):
        print('No icons found. Run:  python3 tool/native/make_icons.py')
        return 1

    a = os.path.join(ROOT, 'android')
    i = os.path.join(ROOT, 'ios')

    print('Android')
    if os.path.isdir(a) and os.listdir(a):
        android(a)
    else:
        _say(warn, 'android/ is empty — run `flutter create . --platforms=android,ios '
                   '--org pro.banksheet --project-name banksheet_mobile` first, then re-run this')

    print('iOS')
    if os.path.isdir(i) and os.listdir(i):
        ios(i)
    else:
        _say(warn, 'ios/ is empty — same fix as above')

    print(f'\n{len(ok)} applied, {len(warn)} skipped')
    return 0 if not warn else 2


if __name__ == '__main__':
    sys.exit(main())
