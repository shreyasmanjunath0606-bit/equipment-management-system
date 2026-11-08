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

## Backend pieces this app needs

- **Database migrations** in `../supabase/migrations/`. The checks, findings and reminders schema is `20261108000001_checks_findings.sql`. One worker per equipment, and the Daily / Weekly / Monthly workbook slots, are in `20261110000001_worker_equipment_assignment.sql`: managers set them up under **Assignments**, and a worker only sees the checks of the equipment assigned to them.
- **Edge Function `admin-users`** in `../supabase/functions/admin-users/`. It handles inviting and deactivating users. Deploy it with:
  `supabase functions deploy admin-users`
- **Supabase → Authentication → URL Configuration.** Add the web app's URL and `com.equipmentportal.app://auth-callback` to the redirect URLs.

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
