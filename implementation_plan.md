# Equipment Management System – Implementation Plan

## 1. Context

Factories need a single place to see the health of every machine. Today a failure is likely communicated verbally or on paper, so nothing is tracked and history is lost. The goal:

- A worker opens a web portal (usually on a phone or shop-floor tablet) and reports/updates the status of a piece of equipment in under 30 seconds.
- The status is stored on a server.
- A factory manager sees the live status of all equipment on a dashboard.
- Any record can be looked up a year or more later (full history, never overwritten).

**Key design decision:** never overwrite status. Every update is an *append-only event* in a history table. "Current status" is just the latest event. This is what makes "what happened to Machine X in Nov 2026?" answerable forever.

## 2. Scope

**MVP (v1)**
- **Multi-plant**: several plants under one company; every machine, area and user belongs to a plant; managers see only their plant(s), admins see all
- **Personal-phone (BYOD) workers**: installable mobile web app (PWA), no app-store install, stay logged in, invite-link onboarding, camera-friendly
- Login with roles: Worker, Supervisor/Manager, Admin (company-wide)
- Equipment registry with no fixed size: admins add, edit and retire machines at any time (QR code per machine, bulk CSV import for many at once)
- User management with no fixed size: admins add users, change roles and deactivate people who leave (history keeps their name)
- Status update form using an admin-configurable status list (defaults: Running / Degraded / Down / Under Maintenance) + failure note + optional photo
- **In-app notifications for managers** (bell icon with unread count, live via Realtime) whenever equipment goes Down/Degraded or recovers
- Manager dashboard: live status overview, filters (area, status), currently-down list
- Equipment detail page: full status timeline
- History search & filters by date range, equipment, status, reporter; CSV export
- Audit trail (who/what/when), no hard deletes

**Later (v2+)**: out-of-app alerts (email/SMS/push/WhatsApp), escalation if a failure is not acknowledged, downtime & MTTR/MTBF reports, maintenance work orders, spare-parts tracking, preventive-maintenance schedules, sensor/IoT integration, multi-plant support.

**Non-goals for MVP:** work-order workflows, inventory, IoT.

## 3. Recommended Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Database | PostgreSQL (hosted via **Supabase**) | Reliable, relational, point-in-time backups, built-in auth & row-level security. A Supabase MCP is already connected in this environment. |
| Backend/API | Supabase (auto REST + RLS) + small server functions where needed | Minimal code to maintain for a solo build |
| Frontend | **Next.js (React) + TypeScript + Tailwind**, PWA-enabled | Mobile-friendly for workers, installable on phone home screen |
| File storage | Supabase Storage (failure photos) | Same auth rules as DB |
| Hosting | Vercel (frontend) + Supabase (backend) | Cheap, low ops |
| QR codes | `qrcode` npm lib | Scan machine → opens its update page directly |

Hosting is **cloud-only** (confirmed). No on-premise variant is planned.

## 4. Data Model (PostgreSQL)

```
users            (id, name, email, role[worker|manager|admin], active, deactivated_at, created_at)
plants           (id, name, code, timezone, active)       -- e.g. "Pune Plant"
areas            (id, plant_id, name)                     -- e.g. "Assembly Line 2"
user_plants      (user_id, plant_id)                      -- which plants a user may access (admins: all)
invites          (id, email, role, plant_ids, token_hash, expires_at, used_at)
equipment        (id, tag_code UNIQUE, name, type, plant_id, area_id, manufacturer, model,
                  serial_no, install_date, is_active, created_at)
status_types     (id, key, label, color, is_failure, sort_order, active)  -- admin-editable
status_events    (id, equipment_id, status_type_id, note, photo_url,
                  reported_by, reported_at, created_at)  -- APPEND-ONLY
equipment_current_status  (VIEW or table) -- latest status_event per equipment
notifications    (id, user_id, equipment_id, status_event_id, message, read_at, created_at)
audit_log        (id, actor_id, action, entity, entity_id, before, after, at)
```

Rules:
- The factory has no existing status scheme, so statuses are rows in `status_types`, not a hard-coded enum. We seed sensible defaults (Running, Degraded, Down, Under Maintenance) and admins can rename/add/hide them without code changes. Old events keep pointing to their status even if it is later hidden.
- Users are never deleted: deactivating blocks login but old events still show who reported them. Machines likewise are retired, not deleted.
- **Plant scoping:** every RLS policy checks the row's `plant_id` against the caller's `user_plants`. A worker/manager in Plant A can never read or report on Plant B equipment. Admins are company-wide. Notifications go only to active managers of the equipment's plant (plus admins). Timestamps stored in UTC, displayed in the plant's timezone.
- Nothing is sized for a specific count; lists are paginated and searchable, so 20 or 20,000 machines behave the same.
- Notifications: a DB trigger on `status_events` inserts one `notifications` row per active manager/admin when the new status has `is_failure = true` or when a failing machine returns to Running. The UI subscribes via Supabase Realtime, shows a bell with unread count, and managers can mark as read.
- `status_events` is insert-only: RLS + DB trigger block UPDATE/DELETE. Corrections are new events.
- Equipment is soft-deleted (`is_active=false`), never removed, so old history keeps its reference.
- Index `(equipment_id, reported_at DESC)` and `(reported_at)` for fast history queries. Volume is tiny (thousands of rows/year), so a year-plus of data is no performance concern.
- `equipment_current_status` uses `DISTINCT ON (equipment_id)` ordered by `reported_at DESC`.

## 5. Long-Term Retention ("accessible after 1 year")

- No legal retention period applies, so there is no mandated limit. We still keep all events indefinitely (no auto-purge) because the data is tiny and the manager wants it available after 1 year and beyond. Notifications may be pruned after e.g. 90 days; status events never.
- Daily automated backups + point-in-time recovery enabled (Supabase Pro) – verify with a restore test.
- Weekly/monthly CSV export of `status_events` to separate storage (cheap off-site copy).
- History UI uses date-range filters + pagination so old data is as easy to reach as new data.
- Schema changes only through versioned migrations so old records stay readable.

## 6. Security & Access

- Auth (personal phones): admin/manager sends an **invite link**; the worker sets a password once and the session is kept (long-lived refresh token), so the QR-scan flow is just scan → tap status → submit. Optional phone-OTP login later.
- BYOD privacy: collect only name, email, role and plant; no location, contacts or device tracking. Deactivating a user revokes sessions immediately, so a person who leaves loses access even though their phone still has the app.
- QR links work even when logged out: user logs in, then is returned to that machine's update page. A worker scanning a machine from another plant is told they don't have access.
- Roles enforced by Postgres **Row-Level Security**, not only in UI:
  - Worker: read equipment, insert status events, view own reports
  - Manager: read everything, export, manage areas
  - Admin: manage users & equipment
- HTTPS only, secrets in environment variables, rate-limit login, validate photo type/size (≤5 MB).

## 7. Application Structure

```
/app
  /(auth)/login
  /equipment               list + filters
  /equipment/[id]          detail + timeline + "Update status" button
  /equipment/[id]/update   fast mobile form (reachable via QR)
  /dashboard               manager overview (counts per status, down list, recent events)
  /history                 search/filter/export across all equipment
  /admin/equipment|users|areas
/lib       supabase client, types, status constants
/supabase/migrations   versioned SQL
```

Dashboard shows: tiles (Running / Degraded / Down / Maintenance), a "Down right now" list with duration, recent activity feed. Auto-refresh via Supabase Realtime subscription.

## 8. Phased Delivery

| Phase | Deliverable | Est. |
|---|---|---|
| 0 | Confirm requirements with factory (statuses, roles, #machines, hosting) | 1–2 d |
| 1 | Supabase project, schema migrations (incl. plants & plant-scoped RLS), seed data | 3–4 d |
| 2 | Auth + role handling, user add/deactivate, app shell | 2–3 d |
| 3 | Equipment CRUD + QR code generation + status-type admin + CSV import | 3–4 d |
| 4 | Status update form (mobile-first, PWA, offline queue) + photo upload + invite onboarding | 4–5 d |
| 5 | Manager dashboard + equipment timeline + in-app notifications (trigger, bell, mark-read) | 4–5 d |
| 6 | History search, filters, CSV export | 2 d |
| 7 | Backups, audit log, security review, load/restore test | 2 d |
| 8 | Pilot on one production area, gather feedback, fix | 1–2 wks |
| 9 | Plant-wide rollout + worker training (1-page guide) | 1 wk |

Roughly 4–5 weeks of build for a solo developer, plus pilot.

## 9. Testing & Verification

- **DB tests:** worker cannot UPDATE/DELETE `status_events`; worker cannot read admin pages' data; current-status view returns latest event.
- **Unit/integration:** status form validation, role-based route guards (Vitest/Jest + Playwright).
- **E2E (Playwright):** worker logs in → scans/opens machine → sets "Down" with note → manager dashboard shows it Down within seconds → history page shows the entry.
- **Notifications:** a worker reports Down → every active manager gets exactly one notification in real time; deactivated managers get none; recovery to Running notifies too; non-failure statuses do not notify.
- **Dynamic data:** deactivate a user and retire a machine → their old events still display; rename a status type → history still renders.
- **Retention check:** insert events with `reported_at` > 13 months ago; confirm they appear in history and export.
- **Restore drill:** restore a backup into a scratch project and verify row counts match.
- **Plant isolation:** user in Plant A cannot read, report on or get notifications for Plant B (RLS tests with two seeded plants); admin sees both.
- **BYOD:** invite link works once and expires; deactivated user's existing session is rejected; offline report syncs after reconnect without duplicates; run the flow on a real low-end Android phone and an iPhone on weak mobile data.

## 10. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Workers don't want work apps on personal phones | No install required (open in browser, optional add-to-home-screen), no data collection beyond the report, light data usage |
| Workers find it slow/annoying → don't use it | ≤3 taps flow, QR scan, big buttons, pilot first |
| Poor signal on shop floor (personal data plans / patchy Wi-Fi) | PWA offline queue for status submissions is **in v1** (stores report locally, syncs when online); photos compressed client-side to ~300 KB |
| Wrong/forgotten status updates | Show "last updated" age; manager can post correction events |
| Data loss | PITR backups + off-site CSV exports + restore drill |
| Shared logins | One account per worker; audit log |
| Notification fatigue / missed alerts (in-app only) | Only notify on failure/recovery; dashboard "Down right now" list as backstop; email/WhatsApp in v2 |

## 11. Decisions (resolved)

1. Hosting: cloud (Vercel + Supabase).
2. Machine and user counts: unbounded and changing; handled by admin-managed, soft-deleted records and paginated lists.
3. Statuses: factory has none, so we ship defaults as configurable `status_types`.
4. Alerts: in-app notifications for managers at launch; external channels deferred to v2.
5. Legal retention: none required; we keep everything indefinitely anyway.

6. Plants: **several plants**; data is plant-scoped, managers see their plant(s), admins see all.
7. Devices: workers use **personal phones**; PWA + invite links + offline queue, no app-store app.

## 12. First Steps After Approval

1. Save this file as `implementation_plan.md` in the project folder.
2. Scaffold Next.js + TypeScript + Tailwind app; create Supabase project.
3. Write migration #1 (tables, indexes, append-only trigger, RLS) and seed a few sample machines.
4. Build the status-update flow end-to-end first (thin vertical slice), then dashboard.

## 13. Implementation Status (updated 2026-11-05)

**Done (builds and typechecks; not yet exercised against real users/data):**
- Supabase project `hwdadnmarnmxewwqcegf` restored; migrations `20261105000001_init.sql` and `20261105000002_harden_function_privileges.sql` applied (tables, plant-scoped RLS, append-only history, notification trigger, photo bucket, default statuses).
- Next.js app: login, invite/set-password flow, equipment list/detail/timeline, mobile report form with photo + offline queue, QR page, manager dashboard with live refresh, notification bell, history with filters + CSV export, admin pages for plants, equipment (incl. bulk import) and users (invite, deactivate, plant assignment).

**Not done yet:**
- Admin UI to edit status types and areas (edit in DB for now)
- Service worker (offline app shell); the offline *report queue* works only while the page is open
- Automated tests (RLS tests, Playwright E2E)
- Deployment to Vercel, backups/PITR check, tighter photo-read policy (currently any active user with the path)

**To run locally**
1. Put the service_role key in `.env.local` (`SUPABASE_SERVICE_ROLE_KEY`).
2. In Supabase: Authentication → disable public sign-ups; add `http://localhost:3000/auth/confirm` to redirect URLs.
3. Bootstrap the first admin (one-time SQL), then invite yourself from Dashboard → Authentication → Invite user:
   `insert into public.invites (email, name, role, expires_at) values ('you@example.com','Your Name','admin', now() + interval '30 days');`
4. `npm run dev`, sign in, create a plant, add equipment, invite a manager and a worker.
