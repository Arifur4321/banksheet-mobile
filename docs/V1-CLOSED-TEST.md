# BankSheet Pro Mobile — v1.0 closed test

**The runbook for getting this app in front of twelve testers on Google Play.**
Read this before touching anything. `../README.md` remains the deep handover for
the Laravel inventory, the three patches and the IAP mechanics; this file is the
v1 scope, what changed to get there, and every command in order.

*Written 4 August 2026.*

---

## 1. What v1 is

A **PDF reader** that also carries the workspace. That ordering is the product
decision behind every other decision in this document.

| | |
|---|---|
| **Signed out** | Open, read, share any PDF on the phone. No account, no network, no permission prompt. Three tabs: Read · Tools · More. |
| **Signed in** | The above plus conversions, bank-statement extraction, e-signature, barcodes, exports and billing. Four tabs: Read · Documents · Tools · More. |

**In scope:** PDF reader · conversion tools (PDF↔DOCX, image→PDF, merge, split,
edit) · bank statement → Excel · e-signature · barcode generation and barcode
on PDF · in-app purchase.

**Built but hidden for v1** — flags in `lib/core/config/feature_flags.dart`:
review queue, web extraction, templates, extraction profiles, generated PDFs,
API keys, dashboard tab. Nothing was deleted. Any of them returns with one
`--dart-define` and no code edit:

```bash
flutter run --dart-define=BANKSHEET_FEATURE_WEB_EXTRACTION=true
```

### Why the reader leads

A first-run user who meets a login wall uninstalls, and a store reviewer who
meets one reads it as a wall rather than a product. The reader needs no account
because it only ever touches files the user already has. Every metered action —
conversion, extraction, signature, barcode — requires a session, which is also
what makes the free tier enforceable: quota lives on the server in
`PlanEnforcementService`, where clearing app data cannot reset it.

---

## 2. Plans

| Plan | Price | Conversions · statements · e-sign · barcodes | Store product |
|---|---|---|---|
| **Free** | €0 | 10 / month each | — |
| **Starter** | €20 / month | 200 / month each | `pro.banksheet.starter.monthly` |
| **Professional** | €49 / month | 1000 / month each, plus API | `pro.banksheet.professional.monthly` |

Reading is unlimited on every tier, including Free.

Defined in `laravel-mobile/config/mobile_plans.php`. The website's
`config/plans.php` is **not touched** — that was the explicit constraint.

> ### ⚠ One decision is still open, and it blocks production (not the closed test)
>
> `mobile_plans.php` currently drives **display only**. Enforcement still reads
> `config/plans.php`, so the app will show "200" while the server counts against
> the web number.
>
> This is not an oversight — the alternative is incoherent. A company has one
> `plan` column and one usage table, so it cannot truthfully have 200
> conversions on a phone and a different number on the web. Three ways out, in
> the file's header comment: **(A)** adopt these numbers everywhere, **(B)** add
> `starter_mobile` / `professional_mobile` plan keys with their own quotas and
> hide them from the web pricing page, **(C)** treat the numbers as copy only.
>
> **Recommended: B.** Fine to run a closed test with your own testers before
> deciding. Not fine to ship publicly.
>
> Separately: web Professional is €79, mobile Professional is €49. Confirm that
> is deliberate — and note Play takes 15–30%, so €49 in-app nets roughly €34–41.

---

## 3. Architecture as it now stands

```
mobile-app-banksheet/
├── lib/
│   ├── main.dart                    Bootstrap: prefs → keychain → SQLite → identity
│   ├── app/
│   │   ├── router.dart              Auth gate + guest allow-list + flag-gated routes
│   │   ├── routes.dart              Every path and name, viewer routes added
│   │   └── shell.dart               Bottom nav, built per session (guest vs signed in)
│   ├── core/
│   │   ├── config/
│   │   │   ├── app_config.dart      Base URL, timeouts, IAP product ids
│   │   │   └── feature_flags.dart   ← NEW. What this build ships.
│   │   ├── storage/
│   │   │   ├── local_db.dart        ← NEW. SQLite: recent files + guest counters
│   │   │   ├── prefs.dart           Non-secret preferences
│   │   │   └── secure_store.dart    Keychain: refresh token + device id
│   │   ├── network/                 ApiClient, interceptor, endpoints, token store
│   │   ├── theme/                   tokens · typography · app_theme
│   │   └── widgets/                 scene_3d · hero_scenes · app_card · states
│   └── features/
│       ├── viewer/                  ← NEW. The reader.
│       │   ├── data/recent_files_repository.dart
│       │   └── presentation/{providers,viewer_home_screen,pdf_viewer_screen}.dart
│       ├── auth · dashboard · documents · tools · barcode · signatures
│       ├── exports · billing · settings · more            (shipped in v1)
│       └── review · web_extraction · templates · profiles (built, flag-hidden)
└── docs/V1-CLOSED-TEST.md           this file
```

### Data: what lives where

| | Server (MySQL on the VPS) | Phone (SQLite) |
|---|---|---|
| Users, companies, plans, quotas | ✅ authoritative | ❌ never |
| Documents, transactions, balances, IBANs | ✅ authoritative | ❌ **never** |
| Files (PDFs, exports, signed docs) | ✅ on disk | ❌ never persisted |
| Recent-file list (path, name, size, page count) | ❌ | ✅ |
| Guest usage counters | ❌ | ✅ advisory only |

**The rule:** *if the app is deleted right now, nothing is lost.* The phone holds
a list of filenames and three integers. It holds no financial data, because that
data belongs to our customers' clients, an offline phone cannot honour a GDPR
erasure request, and `sqflite` writes plaintext. Adding a `transactions` table
here is a decision with a DPIA attached, not a refactor.

### The 3D design system

Already present and reused, not rebuilt: `Scene3D`, `DepthLayer`, `GlowOrb`,
`TiltCard` in `core/widgets/scene_3d.dart`, and ten hero scenes in
`hero_scenes.dart` driven by the site's own 7-second timeline
(`AppMotion.sceneCycle`). Every top-level screen opens with a `HeroPanel`
carrying its scene; the new reader home uses `DocumentsScene`.

Colours, radii, spacing and motion are lifted verbatim from the website's
Tailwind output — see the header of `core/theme/tokens.dart`. Do not "improve"
them: drift there is drift between the two clients.

---

## 4. What changed in this pass

### New files

| File | Purpose |
|---|---|
| `lib/core/config/feature_flags.dart` | 12 `bool.fromEnvironment` flags. One place decides what ships. |
| `lib/core/storage/local_db.dart` | SQLite. Recent files + guest meters, `PRAGMA user_version` migration ladder, LRU trim at 50 rows, `wipeAll()` on sign-out. Opens in **application support**, not documents — the documents directory is iCloud-backed on iOS and would ship customer filenames into Apple's servers under the user's own account. |
| `lib/features/viewer/data/recent_files_repository.dart` | Picking PDFs, remembering opens, dropping rows whose file the OS reclaimed. |
| `lib/features/viewer/presentation/providers.dart` | Recent files + guest usage providers. |
| `lib/features/viewer/presentation/viewer_home_screen.dart` | The reader tab: hero panel, tools card, recents. |
| `lib/features/viewer/presentation/pdf_viewer_screen.dart` | The reader. **The only file that imports `pdfx`** — swapping renderer is a one-file change. |
| `laravel-mobile/config/mobile_plans.php` | Free / Starter / Professional, with the open decision documented in its header. |

### Modified files

| File | Change |
|---|---|
| `pubspec.yaml` | `pdfx` added under files-and-media. **Version constraint written offline — run `flutter pub add pdfx` to pin the real one.** |
| `lib/app/routes.dart` | `viewer` + `pdfView` routes appended. Path is a query parameter, not a segment — filesystem paths contain slashes. |
| `lib/app/router.dart` | Guest allow-list (`_guestPaths`), landing on the reader instead of the dashboard, every flagged route wrapped in `if (Features.x)`. |
| `lib/app/shell.dart` | Now a `ConsumerWidget`; destinations built per session so signing in adds the Documents tab without a restart. |
| `lib/core/providers.dart` | `localDbProvider`, `LocalDb` added to `Bootstrap`. |
| `lib/main.dart` | Opens the database during bootstrap so recents render on frame one. |

`CONTRACT.md` said `lib/core/` was final. That rule existed to stop six parallel
build agents colliding in shared files; the build is finished, so it has done its
job. The exception is noted deliberately rather than taken silently.

---

## 5. Setup — first run on your machine

`android/` and `ios/` are **empty**. Nothing builds until they exist.

```powershell
cd C:\Arifur-work\BankSheet\mobile-app-banksheet

# Generates android/ and ios/ for YOUR Flutter version.
# Does NOT touch lib/, test/, assets/ or pubspec.yaml.
flutter create . --platforms=android,ios --org pro.banksheet --project-name banksheet_mobile

# Pins the real pdfx version and writes pubspec.lock. Do this before pub get.
flutter pub add pdfx

flutter pub get
flutter analyze
flutter test
```

`flutter analyze` has **never been run on this codebase** — it was written in a
sandbox with no pub.dev access. Expect lint nits. The structural work was
verified by `tool/verify_dart.py` (see README §13); the analyzer is the check
that has not happened yet.

### Android configuration `flutter create` does not set

`android/app/build.gradle.kts`:

```kotlin
android {
    namespace = "pro.banksheet.mobile"
    compileSdk = 36
    defaultConfig {
        applicationId = "pro.banksheet.mobile"
        minSdk = 24          // Android 7.0
        targetSdk = 36       // MANDATORY for new Play submissions from 31 Aug 2026
    }
}
```

`android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="com.android.vending.BILLING" />
```

Do **not** add `READ_EXTERNAL_STORAGE`. The app uses the system photo picker and
SAF; declaring broad storage access triggers a Play policy review it does not
need.

For testing against a local Laravel only, add to `<application>`:

```xml
android:usesCleartextTraffic="true"
```

**Remove it before any release build.** Android blocks plain HTTP by default and
that is the correct production behaviour.

---

## 6. Testing against your laptop over USB

Do this before anything touches the VPS.

```powershell
# Terminal 1 — Laravel
cd C:\Arifur-work\BankSheet\docuflow
php artisan serve

# Terminal 2 — route the phone's localhost down the USB cable
adb reverse tcp:8000 tcp:8000

flutter run `
  --dart-define=BANKSHEET_BASE_URL=http://localhost:8000 `
  --dart-define=BANKSHEET_ENV=dev
```

`adb reverse` means no Wi-Fi, no IP addresses and no firewall rules. Confirm the
phone is visible first with `flutter devices`.

> iPhone builds need a Mac. Android only from Windows.

---

## 7. Deploying the Laravel side

The mobile API is **not in docuflow yet** — `laravel-mobile/` is a staging tree,
not a package, and its controllers import docuflow's own Models, Jobs and
Services, so it cannot run anywhere else.

### 7.1 Merge locally

```powershell
cd C:\Arifur-work\BankSheet
Copy-Item .\laravel-mobile\app,.\laravel-mobile\config,.\laravel-mobile\database,.\laravel-mobile\routes,.\laravel-mobile\tests `
          -Destination .\docuflow\ -Recurse -Force
```

Every destination path is new; nothing is overwritten.

### 7.2 Apply the three patches by hand

From `laravel-mobile/docs/`, each with full before/after:

| Patch | File | What it does |
|---|---|---|
| `PATCH-bootstrap-app.md` | `bootstrap/app.php` | Registers `routes/mobile.php` with an **empty** middleware stack, aliases the three mobile middleware, renders validation errors in the mobile envelope. |
| `PATCH-console-routes.md` | `routes/console.php` | Two schedule entries: hourly store reconciliation, daily token prune. Append only. |
| `PATCH-BillingController.md` | `app/Http/Controllers/BillingController.php` | Blocks a store-billed workspace from also starting a Stripe subscription. Zero behaviour change on day one. |

> The empty middleware array in patch 1 is a security boundary, not a
> micro-optimisation. If a browser session cookie could authenticate this API, a
> CSRF against the website would reach every mobile endpoint. Do not tidy it
> into `api:`.

### 7.3 Verify locally

```bash
cd C:\Arifur-work\BankSheet\docuflow

php -l routes/mobile.php
php artisan route:list --path=api/mobile    # expect 63 routes, all named mobile.v1.*
php artisan test --filter=Mobile
vendor/bin/pint --test
php artisan test                            # full suite — the count must NOT move
```

That last line is the real check. The mobile layer is additive; if the existing
suite count changes, something was overwritten.

### 7.4 Commit, push, deploy

```bash
# Local
git checkout -b feature/mobile-api
git add .
git commit -m "Add mobile API v1 and closed-test plan catalogue"
git push -u origin feature/mobile-api
```

```bash
# VPS
ssh arif@<host>
cd /var/www/docuflow

# 1. BACKUP FIRST. Non-negotiable.
mysqldump -u docuflow_user -p docuflow | gzip > ~/docuflow-$(date +%F-%H%M).sql.gz

# 2. Deploy
php artisan down
git pull origin feature/mobile-api
composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan config:clear && php artisan config:cache
php artisan route:clear  && php artisan route:cache
php artisan view:clear
php artisan up

# 3. THE STEP EVERYONE FORGETS
#    A running worker holds the OLD code in memory and does not know the new
#    job classes. Without this, mobile uploads fail with no useful error.
php artisan queue:restart

# 4. Verify
php artisan route:list --path=api/mobile | head -20
curl -s https://banksheet.pro/api/mobile/v1/config | head -40
```

### 7.5 Two server settings that will bite you

```bash
# Nginx default is 1 MB. The app uploads up to 20 MB. Without this, every
# upload over 1 MB dies with a bare 413 that never reaches Laravel — nothing
# in your logs, just a generic failure in the app.
grep -rn 'client_max_body_size' /etc/nginx/
# needs: client_max_body_size 25M;  in the banksheet.pro server block

# PHP has to clear 20 MB too.
php -i | grep -E 'upload_max_filesize|post_max_size'
```

### 7.6 Rollback

Nothing existing is altered, so backing out is a revert plus dropping five
tables:

```bash
git revert <sha> && php artisan migrate:rollback --step=5
```

Write the exact command down before you start, not after.

---

## 8. Play Console — closed test

```powershell
# Signing key. Back this up somewhere you will still have in five years —
# losing it means you can never update the app under this package name again.
keytool -genkey -v -keystore banksheet-upload.jks -keyalg RSA -keysize 2048 `
        -validity 10000 -alias upload

# android/key.properties  (git-ignore it)
#   storePassword=...
#   keyPassword=...
#   keyAlias=upload
#   storeFile=C:\\path\\to\\banksheet-upload.jks

flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

### Checklist

- [ ] `targetSdk = 36` — mandatory for new submissions from **31 Aug 2026**
- [ ] Upload an **AAB**, not an APK
- [ ] Data Safety form — declare: Files and docs (stored on device: the recent
      list), Personal info (email, for the account). **Do not** declare
      Financial info stored on device — the app deliberately does not do that.
- [ ] Privacy policy URL — `https://banksheet.pro/privacy`
- [ ] Create the two subscription products in Play Console with **exactly**
      these ids, or every purchase fails validation:
      `pro.banksheet.starter.monthly` · `pro.banksheet.professional.monthly`
- [ ] Closed testing track → create a tester list → add the testers' Google
      account emails
- [ ] **If your developer account is personal and was created after
      13 Nov 2023: 12 testers must stay opted in for 14 continuous days before
      you can apply for production.** This is the longest-lead item in the whole
      project — start recruiting before the build is finished.

Purchases in a closed test are real Play Billing flows against test accounts —
add your testers as licence testers in Play Console → Setup → Licence testing so
they are not charged.

---

## 9. Known gaps, honestly

| Gap | Impact | Fix |
|---|---|---|
| `flutter analyze` / `flutter test` never run | Unknown lint and test state | §5. Do it first. |
| `pdfx` version constraint written offline | `pub get` may fail to resolve | `flutter pub add pdfx` |
| `pdfx` API used from documentation, not compiled | The viewer may need small adjustments | Contained to one file by design |
| Mobile quotas display-only | App shows 200, server enforces the web number | §2 open decision — pick option B |
| Idempotency keys honoured forever | A legitimate re-upload of the same file months later silently returns the old document. `api_client.dart` says 24 h; the server does not implement it. | Add the time filter in `EnforceApiIdempotency` |
| No push notifications | The app polls `/documents/{id}/status` every 3 s for up to 10 min — up to 200 requests per document | FCM, ~2 h in `ProcessDocumentJob`'s success path. Highest payoff per hour of anything left. |
| Files stream through PHP | Mobile downloads compete with the website for PHP-FPM workers | The `s3` disk is already configured and unused. Pre-signed URLs. |
| Single queue | A 900 s conversion blocks a 5 s upload | Split `high` / `low`, one line per job |
| Apple root CA not in the repo | Every Apple receipt rejected | One `curl` on the VPS — README §6. Irrelevant for a Play-only closed test. |
| iOS untested | No Mac in this loop | Out of scope until the Play test is running |

---

## 10. Order of work

1. `flutter create .` → `flutter pub add pdfx` → `flutter analyze` → `flutter test`
2. Fix whatever the analyzer finds; compile the viewer and adjust the `pdfx` calls if its API differs
3. Test against local Laravel over `adb reverse`
4. Decide the plan-quota question (§2, option B recommended)
5. Merge `laravel-mobile` into docuflow, apply the three patches, run the full test suite
6. Deploy to the VPS — **backup, then `queue:restart`**
7. Point the app at production (no `--dart-define` needed; it is the default)
8. Keystore → signed AAB → Play Console → closed track
9. Recruit 12 testers and start the 14-day clock
