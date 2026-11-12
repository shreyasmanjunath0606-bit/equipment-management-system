# Equipment Portal: Flutter app

The Flutter version of the Equipment Portal. It runs on Android, iOS and the web, using the same Supabase backend as the old Next.js site (project `hwdadnmarnmxewwqcegf`).

## Setup

1. Copy `env.example.json` to `env.json` and fill in the values. `env.json` is gitignored.

   | Key | What it is |
   |---|---|
   | `SUPABASE_URL` | Your Supabase project URL |
   | `SUPABASE_ANON_KEY` | The anon / publishable key (it is public, so it is safe in the app) |
   | `SITE_URL` | Public web address of the deployed app. QR labels link to `SITE_URL/e/CODE` |

2. Install the dependencies: `flutter pub get`

## Run

```sh
flutter run -d chrome --dart-define-from-file=env.json   # web
flutter run -d <android-device> --dart-define-from-file=env.json
```

## Build

```sh
flutter build web --release --dart-define-from-file=env.json   # output: build/web (static files, host anywhere)
flutter build apk --release --dart-define-from-file=env.json   # output: build/app/outputs/flutter-apk/app-release.apk
flutter build ipa --dart-define-from-file=env.json             # needs a Mac + Apple developer account
```

When hosting `build/web`, rewrite every path to `index.html`, so that links like `/e/101-CNC-0001` work on a fresh page load.

## iOS builds (Codemagic)

iOS apps can only be built on a Mac, so `../codemagic.yaml` builds the app on Codemagic's cloud Macs. Every push to `main` that changes `flutter_app/` builds the app and uploads it to TestFlight.

One-time setup:

1. **Apple Developer Program.** Join at developer.apple.com ($99 a year).
2. **App record.** In App Store Connect, go to Apps → + → New App, and use the bundle ID `com.equipmentportal.equipmentPortal`.
3. **API key.** In App Store Connect, go to Users and Access → Integrations → App Store Connect API, and create a key with the **App Manager** role. Download the `.p8` file (you can only download it once) and note the Issuer ID and Key ID.
4. **Codemagic.** Sign in at codemagic.io with GitHub and add this repository.
   - Team settings → Integrations → Developer Portal: add the API key and name it exactly **`Equipment Portal ASC key`**.
   - Team settings → Code signing identities: generate or upload an **iOS Distribution** certificate, then fetch an **App Store** provisioning profile for the bundle ID.
   - App settings → Environment variables: create the group **`supabase`** containing `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SITE_URL`.
5. **First build.** Push to `main`, or start the `iOS → TestFlight` workflow by hand. After Apple finishes processing (about 10–30 minutes), add testers in App Store Connect → TestFlight.

App icons are generated from `assets/icon/` with `dart run flutter_launcher_icons`. See the note in `pubspec.yaml` about the one Xcode setting you need to revert after running it.

## Backend pieces this app needs

- **Database migrations** in `../supabase/migrations/`. The checks, findings and reminders schema is `20261108000001_checks_findings.sql`. One worker per equipment, and the Daily / Weekly / Monthly workbook slots, are in `20261110000001_worker_equipment_assignment.sql`: managers set them up under **Assignments**, and a worker only sees the checks of the equipment assigned to them.
- **Edge Function `admin-users`** in `../supabase/functions/admin-users/`. It handles inviting and deactivating users. Deploy it with:
  `supabase functions deploy admin-users`
  Then set the secret that limits which websites may call it and where invite links may return:
  `supabase secrets set ALLOWED_ORIGINS=https://your-app.vercel.app` (comma-separated if there are several).
- **Supabase → Authentication → URL Configuration.** Add the web app's URL and `com.equipmentportal.app://auth-callback` to the redirect URLs.
- **Supabase → Authentication → Sign In / Providers.** Turn off "Allow new users to sign up" (invites still work), and turn on leaked-password protection.
- **Security hardening** is in `20261112000001_security_hardening.sql`. It covers: failure photos visible only within the plant, findings changeable only by managers and the reporter, status reports no more than 7 days old, verified checks fully locked, and capped stats ranges.

## Tests

```sh
flutter analyze
flutter test                                       # unit tests + screenshot tests
flutter test test/screenshots --update-goldens     # refresh design screenshots in test/screenshots/goldens/
```

## Code layout

| Folder | Contents |
|---|---|
| `lib/core/` | Theme and design tokens, shared widgets, router (with role guards), env config |
| `lib/data/` | Models, Supabase queries and providers, offline outbox (Hive), Excel import/export |
| `lib/features/` | One folder per area: dashboard, checks, equipment, findings, history, notifications, admin, auth, shell |
