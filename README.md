# BankSheet Pro — Mobile

> ## ▶ Start here for v1.0
>
> The app has been scoped down for a **Google Play closed test** and now leads
> with an in-app PDF reader that works with no account. The current architecture,
> everything that changed, and every command — Flutter setup, USB testing, the
> Laravel deploy and the Play Console checklist — are in
> **[`docs/V1-CLOSED-TEST.md`](docs/V1-CLOSED-TEST.md)**.
>
> This file remains the deep handover: the full Laravel inventory, the three
> patches, the IAP mechanics and the design-system reference.



Flutter client for the BankSheet Pro SaaS already running at **https://banksheet.pro**.

This file is the complete handover: what was built, what changed on the server, how to deploy
it, and why each decision was made. If you are picking this up cold — or handing it to another
session — read this file first and you will not need to re-derive anything.

*Last updated: 4 August 2026.*

---

## Table of contents

1. [Context](#1-context)
2. [Quick start](#2-quick-start)
3. [Where everything lives](#3-where-everything-lives)
4. [Laravel side — full inventory](#4-laravel-side--full-inventory)
5. [The three patches to existing files](#5-the-three-patches-to-existing-files)
6. [Environment variables](#6-environment-variables)
7. [Deployment — the complete git workflow](#7-deployment--the-complete-git-workflow)
8. [Flutter side — full inventory](#8-flutter-side--full-inventory)
9. [Platform configuration](#9-platform-configuration)
10. [In-app purchase — how the entitlement actually flows](#10-in-app-purchase--how-the-entitlement-actually-flows)
11. [Design system](#11-design-system)
12. [Scope — what is in and what is deliberately out](#12-scope--what-is-in-and-what-is-deliberately-out)
13. [Verification status](#13-verification-status)
14. [Known gaps and next steps](#14-known-gaps-and-next-steps)
15. [Decisions and why](#15-decisions-and-why)

---

## 1. Context

BankSheet Pro is a Laravel 13 / PHP 8.3 SaaS on a self-managed VPS: bank-statement PDF →
reconciled transactions → XLSX/CSV/JSON, plus 13 PDF tools, a barcode generator, a web
contact crawler, templates and e-signature. Billing is Stripe via Laravel Cashier, four plans
(Free / Starter €20 / Professional €79 / Enterprise).

The mobile app is a **client of that same application and that same MySQL database**. No
business rule is reimplemented in Dart. Every mobile endpoint calls the same service class the
Blade controller calls, so a quota change or an extraction fix lands in both clients at once.

Two constraints shaped the whole design:

* **Packagist is unreachable from the build environment.** So the mobile token auth is a port
  of the OAuth server already written and tested in the sibling SEO project, and the Apple/
  Google receipt verification is written against PHP's built-in `openssl`. **No Composer
  dependency was added.** Do not add one without checking that `composer install` still works
  on your box.
* **No paid third-party service.** No RevenueCat, no Firebase, no Sentry, no crash SDK. The
  app logs to an in-memory ring buffer surfaced in Settings → About → Diagnostics.

---

## 2. Quick start

```bash
# ---- Flutter ---------------------------------------------------------------
cd C:\Arifur-work\BankSheet\mobile-app-banksheet

# Generates android/ and ios/ for YOUR Flutter version.
# It does NOT touch lib/, test/, assets/ or pubspec.yaml.
flutter create . --platforms=android,ios --org pro.banksheet --project-name banksheet_mobile

flutter pub get
flutter analyze          # expect lint nits only; see §13
flutter test
flutter run
```

Point at a different backend:

```bash
flutter run --dart-define=BANKSHEET_BASE_URL=https://staging.banksheet.pro \
            --dart-define=BANKSHEET_ENV=staging
```

Default base URL is `https://banksheet.pro` — see `lib/core/config/app_config.dart`.

The server side must be deployed before the app can sign in. That is §7.

---

## 3. Where everything lives

```
C:\Arifur-work\BankSheet\
├── docuflow\                   ← the existing Laravel app (production, UNCHANGED except 3 patches)
├── SEO-BankSheet\              ← unrelated product, untouched
├── laravel-mobile\             ← NEW server files, to be copied into docuflow\
│   ├── app\                    ← 40 new PHP classes
│   ├── config\mobile.php
│   ├── database\migrations\    ← 5 new migrations
│   ├── routes\mobile.php       ← 63 routes
│   ├── tests\Feature\Mobile\
│   └── docs\                   ← the 3 patches + the IAP runbook
└── mobile-app-banksheet\       ← NEW Flutter app (this folder)
    ├── lib\                    ← 146 Dart files, 41,096 lines
    ├── test\
    ├── assets\fonts\           ← Outfit 400–800, the site's own typeface
    ├── tool\verify_dart.py     ← the static verifier described in §13
    └── docs\IMPLEMENTATION_PLAN.html
```

`laravel-mobile/` is a staging tree, not a package. Its contents get copied into `docuflow/`
preserving paths — see §7.

---

## 4. Laravel side — full inventory

**73 files. Every one is new.** Three existing files get additive patches (§5). No existing
controller, service, policy, migration or view is rewritten.

### 4.1 Config

| File | Purpose |
|---|---|
| `config/mobile.php` | Token TTLs, rate-limit buckets, minimum client version, IAP product→plan map, Apple/Google credentials, legal URLs. Everything env-driven; no secret inline. |

### 4.2 Migrations — 5 new tables, no existing table altered

| Migration | Table | Holds |
|---|---|---|
| `2026_08_03_100000_…` | `mobile_access_tokens` | SHA-256 token hash, device name/id/platform/app version, expiry, revocation, last-used |
| `2026_08_03_100001_…` | `mobile_refresh_tokens` | Hash, expiry, revocation, `rotated_to_id` self-FK for reuse detection |
| `2026_08_03_100002_…` | `mobile_devices` | One row per install: platform, device id, push token slot, locale, last seen |
| `2026_08_03_100003_…` | `store_subscriptions` | Apple/Google subscription state, `original_transaction_id`, plan key, status, expiry, auto-renew flag |
| `2026_08_03_100004_…` | `store_notifications` | Raw ASN/RTDN payloads, deduplicated on `notification_uuid` |

### 4.3 Models

`MobileAccessToken`, `MobileRefreshToken`, `MobileDevice`, `StoreSubscription`,
`StoreNotification` — all in the repo's existing PHP-attribute style (`#[Fillable]`,
`#[Hidden]`), matching `app/Models/ApiKey.php`.

### 4.4 Services

| Class | Responsibility |
|---|---|
| `Services\Mobile\MobileTokenService` | Mints `bsm_at_` / `bsm_rt_` tokens (64 random chars, SHA-256 at rest, plaintext never stored). Refresh **rotates**; presenting an already-rotated refresh token revokes the whole chain. Revocation happens **after** the transaction commits — inside it, the `throw` would roll the revocation back and leave the attacker with working tokens. That exact bug was found by tests in the SEO project; the fix is carried over. |
| `Services\Mobile\MobileErrors` | The 26-code error catalogue and the wire envelope. Same shape and philosophy as the existing `Services\Api\ApiErrors`. |
| `Services\Billing\AppleStoreVerifier` | Verifies StoreKit 2 JWS locally: decodes the `x5c` chain, walks it to Apple's pinned root, verifies the ES256 signature, checks bundle id and environment. Optionally calls the App Store Server API when credentials exist. **Fails closed** if the root cert is missing. Never uses the deprecated `verifyReceipt`. |
| `Services\Billing\GooglePlayVerifier` | Service-account JWT (RS256, `openssl_sign`) → OAuth token → `purchases.subscriptionsv2.get`, then **acknowledges** the purchase. Unacknowledged Play purchases are auto-refunded after 3 days. |
| `Services\Billing\EntitlementResolver` | The single precedence rule: live Stripe → newest live store subscription → free. Also `canPurchaseInApp()`, which is the double-billing guard. |
| `Services\Billing\StoreSubscriptionService` | Claim, apply, restore, downgrade. Rejects a receipt already bound to a different company (`purchase_already_claimed`). Everything funnels into the existing `PlanCatalog::applyToCompany()`. |
| `Services\Billing\StoreProductCatalog` | Product id ↔ plan key, from `config/mobile.php`. Rejects unknown products explicitly. |
| `Services\Billing\Concerns\SignsAndVerifiesJwt` | Shared JOSE plumbing for both verifiers and the Pub/Sub endpoint. |

### 4.5 Middleware

| Alias | Class | Does |
|---|---|---|
| `auth.mobile` | `AuthenticateMobileToken` | Bearer → user. Sets **both** `setUserResolver()` and `auth()->setUser()`. Setting only the resolver gives you a controller that sees the user and a policy that does not — a correctly authenticated request returning a baffling 403. |
| `mobile.version` | `EnforceMobileClientVersion` | `X-BankSheet-App` below `config('mobile.min_client_version')` → 426 with an update URL. Default is `0.0.0`, deliberately — a default of `1.0.0` would 426 every client on day one. |
| `mobile.throttle:<bucket>` | `MobileRateLimit` | Buckets: `auth` 5/min, `upload` 20/min, `read` 240/min, `poll` 120/min. |

### 4.6 Controllers — 17 + 2 webhooks

`Mobile\V1\`: `MobileController` (abstract base), `AuthController`, `AccountController`,
`DeviceController`, `ConfigController`, `DashboardController`, `DocumentController`,
`TransactionController`, `ExtractionProfileController`, `ExportController`, `ToolController`,
`BarcodeController`, `WebExtractionController`, `TemplateController`, `GeneratedPdfController`,
`SignatureController`, `ApiKeyController`, `BillingController`.

`Mobile\Webhooks\`: `AppleNotificationController` (ASN v2, JWS-verified, deduped on
`notificationUUID`), `GoogleNotificationController` (Pub/Sub push, always re-queries the Play
API rather than trusting the message body).

### 4.7 Resources — 24

One `JsonResource` per entity under `App\Http\Resources\Mobile\`, plus
`Concerns\NormalizesValues` carrying the three contract rules:

* **a key is never dropped** — an unreadable value is `null`, so the Dart models parse once;
* **confidence is always `certain|high|medium|low`**, never a float;
* **array fields are always present** and `array_values()`-ed.

Money fields are cast to real floats, not the `decimal:2` strings Eloquent returns.

### 4.8 Console

`SyncStoreSubscriptions` (`banksheet:sync-store-subscriptions`) — hourly reconciliation
against both stores. Accepts `--window=<hours>` (default 48) and `--id=<row>`.

### 4.9 Routes — `routes/mobile.php`, 63 endpoints under `/api/mobile/v1`

Public: `GET /config`, `GET /health`, `POST /auth/{register,login,refresh,forgot-password}`,
`POST /webhooks/{apple,google}`.

Authenticated (`auth.mobile`): `/me` (GET/PATCH/DELETE), `/me/password`, `/devices`,
`/dashboard`, `/documents` (+ status, reprocess, file, export, approve-all),
`/transactions`, `/extraction-profiles`, `/exports`, `/tools` (+ conversions), `/barcode`,
`/web-extractions`, `/templates`, `/generated-pdfs`, `/signatures`, `/api-keys`, `/billing`
(+ purchases apple/google/restore).

### 4.10 Tests

`tests/Feature/Mobile/AuthTest.php` — register, login throttle, plaintext token never in DB,
expired/revoked token, refresh rotation, rotated-token reuse revoking the chain, session
cookie does **not** authenticate, `DELETE /me` requires the current password.

`tests/Feature/Mobile/BillingTest.php` — verified purchase grants the plan through
`PlanCatalog`, Stripe customer gets 409, receipt bound to another company gets 409, replayed
notification is a no-op, `EXPIRED` downgrades, one of two live subscriptions expiring keeps
the plan.

---

## 5. The three patches to existing files

Full before/after text is in `laravel-mobile/docs/`. Summary:

### `bootstrap/app.php` — `docs/PATCH-bootstrap-app.md`

Four hunks:

1. **Imports** — the three middleware classes, `Illuminate\Support\Facades\Route`, plus
   `MobileErrors` and `ValidationException` for hunk 4.
2. **Route registration** — a `then:` closure registering `routes/mobile.php` under
   `api/mobile/v1` with an **explicitly empty middleware stack**. That empty array is the
   security boundary: if a session cookie could authenticate this API, a CSRF against the web
   app would reach every mobile endpoint.
3. **Aliases** — `auth.mobile`, `mobile.version`, `mobile.throttle` added alongside the four
   existing ones. The existing four are untouched.
4. **Validation envelope** (recommended, not required) — renders `ValidationException` in the
   mobile error shape for `api/mobile/*` only, so the app meets one error format instead of
   two. The web app and the public `/api/v1` keep the shape their clients already parse.

### `routes/console.php` — `docs/PATCH-console-routes.md`

Append two schedule entries. Every existing entry untouched.

* `banksheet:sync-store-subscriptions` → `->hourly()->withoutOverlapping()`
* `banksheet:prune-mobile-tokens` → `->dailyAt('03:15')->withoutOverlapping()`

No new cron line — your existing `* * * * * php artisan schedule:run` picks these up.

### `app/Http/Controllers/BillingController.php` — `docs/PATCH-BillingController.md`

Three additive hunks: one import, one constructor parameter (`EntitlementResolver`), and one
early return in `subscribe()` that refuses Stripe checkout when a live store subscription
exists. **No existing line is modified or removed.** For every workspace that has never bought
in the app the behaviour is bit-for-bit identical, because the guard's predicate is false
whenever `store_subscriptions` holds no live row — which is every workspace on the day it ships.

---

## 6. Environment variables

Append to the VPS `.env`. Everything has a working default except the store credentials, so
the API works before Apple/Google are configured — only purchases fail, with `store_unavailable`.

```dotenv
# ── Mobile API ────────────────────────────────────────────────────────────
MOBILE_MIN_VERSION=0.0.0                  # raise this to force-update old installs
MOBILE_ACCESS_TTL_SECONDS=1800            # 30 min
MOBILE_REFRESH_TTL_DAYS=30
MOBILE_RATE_AUTH=5
MOBILE_RATE_UPLOAD=20
MOBILE_RATE_READ=240
MOBILE_RATE_POLL=120
MOBILE_DOCUMENT_MAX_KB=20480              # must match DocumentController's max:20480
MOBILE_IMAGES_TO_PDF_MAX_FILES=30

MOBILE_URL_TERMS=https://banksheet.pro/terms
MOBILE_URL_PRIVACY=https://banksheet.pro/privacy
MOBILE_URL_SUPPORT=https://banksheet.pro/contact
MOBILE_URL_UPDATE_IOS=https://apps.apple.com/app/id0000000000
MOBILE_URL_UPDATE_ANDROID=https://play.google.com/store/apps/details?id=pro.banksheet.mobile

# ── In-app purchase ───────────────────────────────────────────────────────
MOBILE_IAP_YEARLY_ENABLED=false

MOBILE_APPLE_BUNDLE_ID=pro.banksheet.mobile
MOBILE_APPLE_ENVIRONMENT=Production        # or Sandbox while testing
MOBILE_APPLE_ISSUER_ID=
MOBILE_APPLE_KEY_ID=
MOBILE_APPLE_PRIVATE_KEY=storage/app/apple/AuthKey_XXXXXXXXXX.p8
MOBILE_APPLE_ROOT_CERT_PATH=storage/app/apple/AppleRootCA-G3.cer

MOBILE_GOOGLE_PACKAGE_NAME=pro.banksheet.mobile
MOBILE_GOOGLE_SERVICE_ACCOUNT_JSON=storage/app/google/play-service-account.json
MOBILE_GOOGLE_PUBSUB_AUDIENCE=https://banksheet.pro/api/mobile/v1/webhooks/google
MOBILE_GOOGLE_PUBSUB_SERVICE_ACCOUNT=
MOBILE_GOOGLE_PUBSUB_TOKEN=
```

**Apple's root certificate is not in the repo** — the build box could not reach apple.com, and
shipping an unpinned chain check would make every receipt forgeable. Fetch it once on the VPS:

```bash
mkdir -p storage/app/apple
curl -fsSL -o storage/app/apple/AppleRootCA-G3.cer \
  https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
chmod 640 storage/app/apple/AppleRootCA-G3.cer
```

Until that file exists, every Apple receipt is rejected with `store_unavailable`. That is
deliberate: fail closed.

Keep `storage/app/apple/` and `storage/app/google/` out of git — the `.gitignore` in
`laravel-mobile/` already covers `*.p8`, `*.p12` and `service-account*.json`.

---

## 7. Deployment — the complete git workflow

Your existing process is: commit locally, push, then pull manually on the VPS. This fits into it.

### 7.1 Local — stage the new files into `docuflow`

Copy `laravel-mobile/`'s contents into the `docuflow` repo, preserving paths. Nothing
overwrites an existing file — every path is new.

**Windows PowerShell:**

```powershell
cd C:\Arifur-work\BankSheet
Copy-Item -Path .\laravel-mobile\app     -Destination .\docuflow\ -Recurse -Force
Copy-Item -Path .\laravel-mobile\config  -Destination .\docuflow\ -Recurse -Force
Copy-Item -Path .\laravel-mobile\database -Destination .\docuflow\ -Recurse -Force
Copy-Item -Path .\laravel-mobile\routes  -Destination .\docuflow\ -Recurse -Force
Copy-Item -Path .\laravel-mobile\tests   -Destination .\docuflow\ -Recurse -Force
```

**git-bash / WSL:**

```bash
cd /c/Arifur-work/BankSheet
cp -r laravel-mobile/{app,config,database,routes,tests} docuflow/
```

Then apply the three patches by hand from `laravel-mobile/docs/`. They are small — one
`then:` closure, three aliases, one exception renderer, two schedule entries, and one early
return in `BillingController::subscribe()`.

### 7.2 Local — verify before committing

```bash
cd C:\Arifur-work\BankSheet\docuflow

php -l routes/mobile.php                    # and any file you edited by hand
php artisan route:list --path=api/mobile    # expect 63 routes, all named mobile.v1.*
php artisan test --filter=Mobile            # the two new test files
vendor/bin/pint --test                      # keep the style gate green
php artisan test                            # full suite — must stay at its current count
```

That last one is the real check. The mobile layer is additive; if the existing suite count
moves, something was overwritten that should not have been.

### 7.3 Local — commit and push

```bash
cd C:\Arifur-work\BankSheet\docuflow
git checkout -b feature/mobile-api

git add app/Http/Controllers/Mobile app/Http/Middleware/AuthenticateMobileToken.php \
        app/Http/Middleware/EnforceMobileClientVersion.php app/Http/Middleware/MobileRateLimit.php \
        app/Http/Resources/Mobile app/Models/Mobile*.php app/Models/Store*.php \
        app/Services/Mobile app/Services/Billing app/Console/Commands/SyncStoreSubscriptions.php \
        config/mobile.php database/migrations routes/mobile.php tests/Feature/Mobile

git add bootstrap/app.php routes/console.php app/Http/Controllers/BillingController.php

git status                  # read it. Nothing unexpected should be staged.
git commit -m "Add mobile API, token auth and in-app purchase entitlement"
git push -u origin feature/mobile-api
```

Merge to your deploy branch when you are happy:

```bash
git checkout main
git merge --no-ff feature/mobile-api
git push origin main
```

### 7.4 VPS — pull and migrate

SSH in, then — substituting your actual path:

```bash
cd /var/www/banksheet          # ← your docuflow path on the VPS

php artisan down --render="errors::503"      # optional; the migration is additive and fast

git pull origin main

# No new Composer package was added, so composer install is only needed if
# composer.lock changed. It did not.
# composer install --no-dev --optimize-autoloader

php artisan migrate --force                  # creates the 5 new tables

php artisan config:clear && php artisan config:cache
php artisan route:clear  && php artisan route:cache
php artisan view:clear
php artisan optimize

# The queue worker holds the old code in memory until it is told to restart.
php artisan queue:restart

php artisan up
```

If you run the worker under supervisor, `queue:restart` is enough — supervisor respawns it.
If you run it under systemd, `sudo systemctl restart banksheet-worker` instead.

### 7.5 VPS — verify the deploy

```bash
# Public, unauthenticated. Should return JSON with plans, locales and tool definitions.
curl -s https://banksheet.pro/api/mobile/v1/config | head -c 400

# Should be 200 and {"status":"ok",...}
curl -s -o /dev/null -w '%{http_code}\n' https://banksheet.pro/api/mobile/v1/health

# Should be 401 with {"error":{"code":"unauthorized",...}} — NOT a redirect to /login.
curl -s https://banksheet.pro/api/mobile/v1/me

# The scheduler picked up the new commands.
php artisan schedule:list | grep -E 'store-subscriptions|prune-mobile-tokens'

# The route table is real.
php artisan route:list --path=api/mobile | wc -l
```

A redirect instead of a 401 on `/me` means the route file was registered with the `web`
middleware group — re-read hunk 2 of `PATCH-bootstrap-app.md`.

### 7.6 Rollback

The migration is purely additive — five new tables, no column added to an existing one, no
data rewritten. To roll back:

```bash
git revert <merge-sha> && git push origin main
# on the VPS
git pull origin main && php artisan migrate:rollback --step=5 && php artisan optimize && php artisan queue:restart
```

Dropping the five tables loses mobile sessions (users sign in again) and the local mirror of
store subscriptions (rebuilt on the next `banksheet:sync-store-subscriptions` run). Nothing
about the website is affected.

### 7.7 The Flutter repo

Separate repo, separate cadence — it releases through the stores, not through your VPS.

```bash
cd C:\Arifur-work\BankSheet\mobile-app-banksheet
git init
git add .
git commit -m "BankSheet Pro mobile app"
git branch -M main
git remote add origin <your-repo-url>
git push -u origin main
```

`.gitignore` already excludes `build/`, `.dart_tool/`, IDE files, signing keys
(`*.p8`, `*.p12`, `key.properties`, `upload-keystore.jks`, `service-account*.json`) and the
generated `android/` + `ios/` folders. **Once you have your own signed release configs, remove
the `/android/` and `/ios/` lines from `.gitignore` and commit those folders** — the signing
setup and the store metadata belong in version control.

Release builds:

```bash
flutter build appbundle --release     # Play — AAB, not APK
flutter build ipa --release           # App Store
```

Bump `version:` in `pubspec.yaml` before every store upload — the build number after the `+`
must increase or the store rejects the binary.

---

## 8. Flutter side — full inventory

**146 Dart files, 41,096 lines.** No code generation anywhere: no freezed, no
json_serializable, no build_runner. `flutter pub get && flutter run` is the whole setup.

### 8.1 Layout

```
lib/
  main.dart                 startup: prefs + keychain read BEFORE the first frame,
                            so a signed-in user never sees the login screen flash
  app/
    app.dart                MaterialApp.router, theme, text-scale clamp (0.85–1.3)
    router.dart             go_router + the declarative auth gate
    routes.dart             every route name and path as a constant
    shell.dart              5-tab bottom nav: Home · Documents · Review · Tools · More
  core/
    config/app_config.dart  base URL, timeouts, IAP product ids, upload cap, poll cadence
    theme/                  tokens.dart · typography.dart · app_theme.dart
    network/                api_client.dart · auth_interceptor.dart · token_store.dart
                            api_exception.dart · endpoints.dart
    storage/                secure_store.dart (Keychain/Keystore) · prefs.dart
    utils/                  json.dart · formatters.dart · logger.dart
    widgets/                scene_3d.dart · hero_scenes.dart · app_card.dart
                            states.dart · page_scaffold.dart
    i18n/strings.dart       every user-visible literal in the app
    providers.dart          the DI root
  features/<name>/
    domain/                 immutable models, hand-written fromJson/copyWith/==
    data/                   repository + its provider
    presentation/           providers, screens, widgets
```

### 8.2 Feature modules — 13

| Module | Screens | Notes |
|---|---|---|
| `auth` | splash, welcome, login, register, forgot password | Session models shared app-wide. Welcome screen is the store-review first impression. |
| `dashboard` | home | 13 KPIs, usage meters, quick actions, recent documents |
| `documents` | list, upload, detail | Upload from Files **or camera scan**; the PDF is built on-device with no extra dependency (`data/image_pdf_builder.dart` — `image` decodes and re-encodes at ≤1600 px / q80, then a hand-written PDF writer emits one `/DCTDecode` XObject per page, all inside `compute()` so the UI never stalls). Detail shows statement summary, reconciliation and paginated transactions. Status polling honours the server's `poll_after_seconds`. |
| `review` | cross-document queue | Swipe to approve/reject with undo; optimistic updates that roll back on failure |
| `tools` | hub, run, history | **Schema-driven**: the 13 tools and their option forms are built from what `GET /tools` publishes, so adding a tool server-side needs no app release |
| `barcode` | generator | 8 symbologies, live debounced preview, PNG/SVG download. Check-digit validation ported exactly from the server so the preview and the button never disagree. |
| `web_extraction` | list, create, detail, results | Progress polling, per-target status, XLSX/CSV export |
| `templates` | templates, detail, generated PDFs | Variable schema rendered as a real typed form |
| `signatures` | list, detail | Signer timeline, audit trail, signed-PDF download. Read-only in v1 — creating requests stays on the website, and the app says so rather than dead-ending. |
| `exports` | archive | Grouped by day, download + share |
| `profiles` | list, detail | Active toggle with optimistic rollback; rules rendered as labelled sections, with the raw JSON behind an "Advanced" expansion |
| `billing` | plan + paywall | §10 |
| `settings` / `more` | more hub, settings, profile, password, language, API keys, about, delete account | 13 locales; in-app account deletion (App Store 5.1.1(v)) |

### 8.3 The pieces worth understanding before changing anything

**`core/network/auth_interceptor.dart` — single-flight refresh.** If five screens fire requests
the moment the access token expires, a naive interceptor performs five refreshes. Because the
server rotates refresh tokens and treats reuse as theft, four of them present an
already-rotated token and the entire session is revoked. So the first 401 starts one refresh,
everyone else awaits the same future, and each queued request is replayed once. It also
refreshes *proactively* when the token is known-stale, turning the common case into one round
trip instead of a 401 plus a retry.

**`app/router.dart` — the auth gate.** One `redirect` reads the session and decides. No screen
ever pushes the login page. The gate holds on splash until the keychain read completes, which
is why `main.dart` awaits `tokens.restore()` before `runApp`.

**`core/i18n/strings.dart` — one file, every literal.** Widgets contain no hard-coded copy. The
app ships English; the user's locale is sent to the server on `PATCH /me` so server-rendered
content (validation messages, plan names, error detail) follows. The website's 13 locale
catalogues (1,881 aligned keys each) are the extraction source when you localise the client.

---

## 9. Platform configuration

`flutter create` does not set these; the stores require them.

### Android — `android/app/build.gradle.kts`

```kotlin
android {
    namespace = "pro.banksheet.mobile"
    compileSdk = 36
    defaultConfig {
        applicationId = "pro.banksheet.mobile"
        minSdk = 24            // Android 7.0
        targetSdk = 36         // MANDATORY for new Play submissions from 31 Aug 2026
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}
```

`android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="com.android.vending.BILLING" />
```

Do **not** add `READ_EXTERNAL_STORAGE` — the app uses the system photo picker and SAF, and
declaring broad storage access triggers a Play policy review it does not need.

### iOS — `ios/Runner/Info.plist`

```xml
<key>NSCameraUsageDescription</key>
<string>BankSheet Pro uses the camera to photograph bank statement pages and turn them into a PDF.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>BankSheet Pro can attach a statement image you have already saved.</string>
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

`ios/Podfile` → `platform :ios, '15.0'` (StoreKit 2 needs iOS 15).
In Xcode, add the **In-App Purchase** capability to the Runner target.

---

## 10. In-app purchase — how the entitlement actually flows

The rule the whole design hangs on:

> A purchase on a phone is a **claim**. It becomes an entitlement only after the server
> verifies it with Apple or Google.

### Why the website honours a mobile purchase with no web-side change

Traced through the existing code:

1. `PlanCatalog::applyToCompany()` writes `companies.plan` **plus all 11 limit columns plus
   `features_json`**.
2. `Company::resolvedPlanKey()` tries Stripe first, then falls back to
   `return $this->plan ?: config('plans.default', 'free');`
3. So a workspace with no Stripe subscription resolves to whatever `companies.plan` says.
4. `StoreSubscriptionService` calls **the same `applyToCompany()`** that
   `SubscriptionLifecycleService` calls for Stripe.

A store grant is therefore byte-for-byte the same mutation Stripe performs. Buy Starter on the
phone → `banksheet.pro` shows Starter immediately. The only web change needed is the
double-billing guard (§5).

### The client's completion rules — `lib/features/billing/data/purchase_service.dart`

* `completePurchase()` **only** after the server returns 200.
* Also complete on a non-retryable 4xx (`purchase_invalid`, `purchase_already_claimed`,
  `subscription_conflict`) — otherwise the transaction re-arrives on every launch forever.
* On a 5xx or network failure, **leave it pending**. The next launch retries it. This is what
  prevents "the user paid and got nothing".
* Pending purchases already in the queue are drained on `init()` — a purchase that completed
  while the app was killed arrives there.
* `canceled` is not an error and shows no red toast.

### Double-billing guard, both sides

* Server: `POST /billing/purchases/*` → 409 `subscription_conflict` when Stripe is live.
* Server: `BillingController::subscribe()` (the patch) refuses Stripe checkout when a store
  subscription is live.
* Client: when `/billing` reports `managed_by: stripe`, every purchase button is hidden.

### Products

```
pro.banksheet.starter.monthly
pro.banksheet.professional.monthly
pro.banksheet.starter.yearly          # built, hidden behind --dart-define=BANKSHEET_YEARLY=true
pro.banksheet.professional.yearly
```

These must match App Store Connect, Play Console **and** `config/mobile.php`'s `iap.products`.

Auto-renew is the stores'. The server learns about renewals from App Store Server
Notifications V2 and Play RTDN, with `banksheet:sync-store-subscriptions` hourly as the safety
net for a notification that never arrived.

Full operator runbook — store setup, ASN URL, Pub/Sub topic, service-account roles, sandbox
testing: **`laravel-mobile/docs/IAP-SETUP.md`** and
**`lib/features/billing/IAP-CLIENT.md`**.

---

## 11. Design system

Tokens are lifted verbatim from the website so the two read as one product. Sources are cited
in `lib/core/theme/tokens.dart`:

| | |
|---|---|
| Canvas | `#F5F5F4` (`bg-stone-100`) |
| Cards | white, radius 24 (`rounded-3xl`), 1 px `#E7E5E4` ring (`ring-stone-200`), soft shadow |
| Text | `#1C1917` / `#44403C` / `#78716C` (stone 900/700/500) |
| Action | `#059669` (emerald-600), active nav `#ECFDF5` on `#065F46` |
| Hero panels | `#0C0A09` (stone-950), accent `#6EE7B7` |
| Brand deep | `#102820` — the site's `<meta name="theme-color">` |
| Typeface | **Outfit** 400–800, bundled in `assets/fonts/` (the site loads the same family from fonts.bunny.net) |

The 3D language is a Flutter port of the site's own `.bs-esign` scene in
`resources/css/app.css`: 1100 px perspective on the *viewport* (not the transformed element —
putting it there makes depth shift as it rotates), depth-separated layers, a blurred bloom at
z −70, a 14° / −13° resting pose, a 9 s float and a 420 ms `cubic-bezier(0.22, 1, 0.36, 1)`
tilt ease.

`lib/core/widgets/scene_3d.dart` provides `Scene3D`, `DepthLayer`, `GlowOrb`, `TiltCard`.
`hero_scenes.dart` composes one scene per section — statement→spreadsheet for the dashboard, a
lifting stack of PDFs for documents, a barcode slab, a signing pen, a node globe for the
crawler, stepped plan cards for billing. All of it respects reduce-motion and stops ticking
when the route is not visible.

---

## 12. Scope — what is in and what is deliberately out

**In:** auth, dashboard, documents (file upload + camera scan → PDF on device),
bank-statement detail with reconciliation, review queue with swipe approve/reject, 13 PDF
tools, barcode generator, web-to-Excel, templates and generated PDFs, e-signature tracking,
export archive, extraction profiles, plan and billing with IAP, settings, API keys, in-app
account deletion.

**Out, by request:** team management, invitations, member roles, company settings.

**Out, by judgement:**

| Not built | Why |
|---|---|
| Advanced PDF Editor | 1,179 lines of Konva + pdf-lib + pdf.js, ~18 tools, redaction rasterisation. A phone is the wrong device for it; rebuilding it natively is 8+ weeks for a screen nobody will use on a 6-inch display. |
| Barcode Studio (drag onto PDF pages) | interact.js drag/resize on rendered pages — same reasoning |
| Signature-field placement | Same |
| Admin | Four paginated tables for you alone |
| Guest / marketing / blog / API docs | Acquisition surfaces for the website. Shipping them in the app adds nothing and risks App Store 4.2 "minimum functionality". |

Where a feature is absent the app says so and points at the website, rather than dead-ending.

---

## 13. Verification status

`flutter analyze` **could not be run where this was built** — pub.dev and the Flutter SDK
mirrors are blocked in that sandbox. A static verifier was written instead:
**`tool/verify_dart.py`** (run it with `python3 tool/verify_dart.py` from the project root).

It reports **0 errors** across 152 files:

* delimiters balanced in every file
* every `import` resolves to a real file
* every `package:` import is declared in `pubspec.yaml`
* every `S.*`, `AppRoute.*`, `AppColors.*`, `AppText.*`, `AppSpacing.*`, `AppRadius.*`,
  `Endpoints.*`, `Fmt.*`, `J.*`, `AppConfig.*`, `Log.*` member exists
* every cross-file type is imported where it is used
* all 34 router-built screen constructors match their declarations (named args accepted,
  required args passed)
* no duplicate public class names across 314 classes
* all 63 referenced providers are declared
* no `print()`, no `TODO`, no deprecated `withOpacity`

Its ~60 remaining warnings are all Flutter SDK types the script's allow-list does not
enumerate (`PopScope`, `ChoiceChip`, `SelectableText`, `AutoDisposeStateNotifierProvider`, …)
— false positives, not findings.

Laravel: **all 73 files pass `php -l`**, all 63 routes resolve to real controller methods,
every error code used exists in `MobileErrors::CATALOG`, every `config('mobile.*')` key exists.

**Not yet done — do this first on your machine:**

```bash
flutter analyze     # expect lint nits; the structural work is verified
flutter test        # 6 test files: auth, document, tools, web_extraction, content, billing, settings
```

The PHP test suite was also not executed here (`vendor/` is not populated in the sandbox). Run
`php artisan test --filter=Mobile` after deploying.

---

## 14. Known gaps and next steps

| Gap | Impact | Fix |
|---|---|---|
| Apple root CA not in the repo | Every Apple receipt is rejected until it is fetched | One `curl` on the VPS — §6 |
| No push notifications | The app polls for document status; polling stops when backgrounded | FCM is ~2 h of backend work in `ProcessDocumentJob`'s success path. Highest UX payoff per hour of anything left. |
| `flutter analyze` not run | Unknown lint count | Run it |
| Documents stored on the local disk, not S3 | Every download streams through PHP on one VPS; mobile multiplies that traffic | The `s3` disk is already configured but unused. Switch the document disk and serve pre-signed URLs before real mobile volume. |
| Queue is the `database` driver, one queue | A 900 s PDF conversion blocks the 5 s mobile upload behind it | Split into `high` (uploads, statements) and `low` (conversions, crawls) with separate workers — one line per job plus a supervisor entry |
| Idempotency TTL documented but not implemented | Keys are honoured forever | Add the time filter in `EnforceApiIdempotency` |
| Google Sign-In / Sign in with Apple | Not in v1 | App Store 4.8 means adding Google drags Sign in with Apple in with it. Ship both together in v1.1; email+password only in v1.0 removes a rejection category from the first submission. |

### Store submission

| | |
|---|---|
| **Play** | target API 36 (**mandatory 31 Aug 2026**) · AAB not APK · Data safety form · if your developer account is *personal* and created after 13 Nov 2023 you need **12 testers opted in for 14 continuous days** before production access — start recruiting early, it is the longest-lead item in the project |
| **App Store** | in-app account deletion (built: Settings → Delete account) · demo account with a populated workspace and a sample statement PDF · the subscription screen must show price, period, auto-renew wording and Terms/Privacy links (built) · Restore purchases visible (built) · no external purchase links anywhere |

Both need a privacy policy URL (`/privacy`) and a support URL (`/contact`) — already served by
your Laravel app.

---

## 15. Decisions and why

**Hand-rolled token auth instead of Sanctum.** Packagist is unreachable from the build
environment, and a half-installed auth package is the worst possible failure mode. The SEO
project already contains a complete, 31-test OAuth token server in the same house style —
opaque tokens, SHA-256 at rest, rotation with reuse detection. Porting it cost less than
fighting Composer and arrived with its bugs already found.

**No code generation in the Flutter app.** freezed and json_serializable are better tools for
a team with CI. For a solo maintainer, `flutter pub get && flutter run` working on a fresh
clone with no build step is worth more than the boilerplate they save. Models are ~40 lines
each and entirely readable.

**Empty middleware stack on the mobile routes.** Registering them through `api:` would attach
the `api` group; through `web:` would attach sessions and CSRF. Neither is right. The explicit
`Route::middleware([])` is the security boundary — a browser cookie must never authenticate
this API.

**Mobile controllers are thin translators.** They validate, call the same service the Blade
controller calls, and shape JSON. There is no `if` in them that exists nowhere else. That is
what "keep all business logic in Laravel" means in practice, and it is why a quota change
lands in both clients at once.

**Resources never drop a key.** Copied from the existing `StatementResponseBuilder` contract.
A Dart model written against a schema whose keys never disappear is a model you write once.

**The canvas editors were not ported.** Honest cost/benefit: 8+ weeks to rebuild an 18-tool
Konva editor for a screen size where nobody will use it. The app links to the website instead.

---

*Everything above was derived by reading the actual source in `docuflow/` and `SEO-BankSheet/`
— every claim about existing behaviour is traceable to a file. Nothing was assumed from
naming or convention.*
