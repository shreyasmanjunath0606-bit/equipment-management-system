# Equipment Portal

Multi-plant equipment management: equipment status reports, QR labels, scheduled checks from Excel sheets, findings and KPI charts.

- **App:** Flutter, for Android, iOS and web. See [`flutter_app/`](flutter_app/README.md) for setup, running and builds.
- **Backend:** Supabase (project `hwdadnmarnmxewwqcegf`). Database migrations are in [`supabase/migrations/`](supabase/migrations) and the `admin-users` Edge Function is in [`supabase/functions/`](supabase/functions).
- **Plans:** [`docs/plans/`](docs/plans) and [`implementation_plan.md`](implementation_plan.md).

## Web hosting

https://equipment-portal-app.vercel.app is the Vercel project `equipment-portal-app` (Root Directory `flutter_app`). Every push to `main` rebuilds it with [`flutter_app/tool/vercel_build.sh`](flutter_app/tool/vercel_build.sh), which needs the `SUPABASE_URL` and `SUPABASE_ANON_KEY` environment variables set in Vercel.

The old Next.js site, equipment-management-system-7etd.vercel.app, is retired and redirects to the new address.
