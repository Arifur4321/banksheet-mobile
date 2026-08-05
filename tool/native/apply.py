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
PACKAGE = 'pro.banksheet.mobile'
KOTLIN_PKG = 'pro.banksheet.banksheet_mobile'
CHANNEL = 'pro.banksheet/incoming_file'
ADAPTIVE_BG = '#102820'   # AppColors.forest

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
                      '    <uses-permission android:name="android.permission.CAMERA" />\n'
                      '    <uses-permission android:name="com.android.vending.BILLING" />\n'
                      '\n    <application', 1)
        _say(ok, 'permissions added (INTERNET, CAMERA, BILLING)')

    if 'application/pdf' not in s:
        # Anchored on the LAUNCHER filter's closing tag, which every
        # Flutter-generated manifest has exactly once.
        anchor = '</intent-filter>'
        filters = (
            '</intent-filter>\n\n'
            '                <!-- Makes BankSheet Pro appear in Android\'s "open with"\n'
            '                     list for a PDF. Without this the app can read PDFs\n'
            '                     perfectly well and no other app will ever offer it\n'
            '                     one. BROWSABLE covers a PDF link tapped in a\n'
            '                     browser; the file:// variant covers older apps and\n'
            '                     file managers that still hand out raw paths. -->\n'
            '                <intent-filter android:label="@string/app_name">\n'
            '                    <action android:name="android.intent.action.VIEW" />\n'
            '                    <category android:name="android.intent.category.DEFAULT" />\n'
            '                    <category android:name="android.intent.category.BROWSABLE" />\n'
            '                    <data android:scheme="content" android:mimeType="application/pdf" />\n'
            '                    <data android:scheme="file" android:mimeType="application/pdf" />\n'
            '                </intent-filter>\n\n'
            '                <!-- "Share -> BankSheet Pro" from any app. -->\n'
            '                <intent-filter android:label="@string/app_name">\n'
            '                    <action android:name="android.intent.action.SEND" />\n'
            '                    <category android:name="android.intent.category.DEFAULT" />\n'
            '                    <data android:mimeType="application/pdf" />\n'
            '                </intent-filter>\n'
        )
        s = s.replace(anchor, filters, 1)
        _say(ok, 'PDF VIEW + SEND intent filters added')

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
