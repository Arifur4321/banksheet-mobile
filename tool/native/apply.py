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
  * android:label -> "BankSheet Pro"
  * VIEW intent filters for application/pdf over content:// and file://, which
    is what puts the app in the chooser
  * SEND intent filter, so "Share -> BankSheet Pro" works too
  * MainActivity.kt that resolves the incoming URI to a real readable file and
    hands the path to Dart over a MethodChannel

iOS
  * AppIcon set at every size, alpha stripped (an icon with an alpha channel is
    rejected at upload)
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
