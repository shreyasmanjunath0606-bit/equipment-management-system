# New Features Plan: Scheduled Checks, Equipment Codes, KPI Graphs, Findings

_Created 2026-11-07. Target: the Flutter app (Android, iOS, Web) on the existing Supabase backend (`hwdadnmarnmxewwqcegf`)._

## Why
Equipment checks are done from daily, weekly and monthly Excel check sheets. Today nothing tracks whether checks were done, when the next one is due, what problems were found, or whether those problems were fixed. These features move the check sheets into the app so that:

- checks repeat on their own,
- people get reminded,
- managers see progress on graphs and get alerted when a deferred problem is still open.

## Features at a glance

| # | Feature | Who uses it |
|---|---|---|
| 1 | Frequency-based schedules from uploaded Excel sheets (daily/weekly/monthly), auto-repeat, reminders | Admin/Manager upload; Workers complete |
| 2 | Unique code per equipment; everything looked up by that code (QR scan) | Everyone |
| 3 | Plan vs actual bar graph (daily): checks completed out of checks planned | Manager/Admin |
| 4 | Cumulative line graph: tasks done vs total tasks to date | Manager/Admin |
| 5 | Problem findings bar graph (daily): problems found while checking | Manager/Admin |
| 6 | Findings solved vs total, line graph | Manager/Admin |
| 7 | Deferred problem: worker schedules a fix time; manager is notified if it is still open after that time | Worker defers; Manager alerted |

## 1. Excel check schedules

**Excel template** (downloadable from the app):

| Equipment Code | Check Item | Frequency | Start Date | Description |
|---|---|---|---|---|
| PUN-CNC-0001 | Check coolant level | Daily | 2026-11-01 | Top up if below mark |
| PUN-CNC-0001 | Clean chip tray | Weekly | 2026-11-01 | |
| PUN-PRS-0003 | Inspect hydraulic hoses | Monthly | 2026-11-07 | |

**Upload flow (Admin/Manager)**
1. Pick an `.xlsx` file. The app parses it on the device.
2. A preview shows every row. Problems are flagged: unknown equipment code, bad frequency, bad date.
3. On confirm:
   - the original file is stored in the private storage bucket `check-sheets`;
   - all rows become `check_items` in one transaction (RPC `import_check_sheet`).

**Recurrence rules** (function `generate_check_tasks`, using the plant's timezone)
- **Daily:** every day from the start date.
- **Weekly:** start date + 7 days, repeating. A start on the 1st gives the 1st → 8th → 15th → 22nd …
- **Monthly:** the same day of each month. 7 Nov gives 7 Dec → 7 Jan … A start on the 31st falls back to the last day of shorter months.
- Each due date creates a row in `check_tasks`. A unique key on (item, date) means re-running never duplicates tasks.

**Scheduled jobs** (Supabase `pg_cron`)

| When | Job |
|---|---|
| Daily 00:05 | Create tasks for the next 7 days; mark past unfinished tasks as **missed** |
| Daily 07:00 | Notify workers of the plant about today's checks; weekly/monthly checks also get a reminder the day before |
| Every 15 min | Check for overdue deferred findings (feature 7) |

**Worker screen "My checks"**
- Tabs: Today / This week / This month / Overdue, grouped by equipment.
- Tick or swipe to complete, with undo. Each equipment shows a progress ring.
- "Report problem" on any item creates a finding.
- Works offline; ticks sync when the connection returns.

**Manager screen "Check sheets"**
- Uploaded sheets and their active items.
- Deactivate an item; download the original file.
- Export completions to Excel.

## 2. Equipment codes
- `equipment.tag_code` is the one unique code. It is unique regardless of upper/lower case.
- If the admin leaves the code blank, one is generated: `<PLANT>-<TYPE>-<0001>`, e.g. `PUN-CNC-0001`.
- The QR label encodes the code. The app's **Scan** button and the web link `/e/<code>` both open that equipment.
- Everything is reachable from the code: details, status timeline, checks, findings and graphs.

## 3–6. Graphs (Dashboard → "Checks & findings")
- Filters: plant, plus a date range of 7 / 30 / 90 days (default 30).
- Data comes from two database functions that respect each user's plant access:
  - `check_stats_daily(plant, from, to)` → day, planned, completed, cumulative planned, cumulative completed
  - `finding_stats_daily(plant, from, to)` → day, found, resolved, cumulative found, cumulative resolved

| # | Chart | Type | Series |
|---|---|---|---|
| 3 | Plan vs actual | Bar (per day) | Planned vs completed |
| 4 | Cumulative completion | Line | Cumulative completed vs cumulative planned (+ % done) |
| 5 | Problem findings | Bar (per day) | Problems found |
| 6 | Findings solved | Line | Cumulative resolved vs cumulative found |

Each chart has a one-line takeaway (e.g. "92% of planned checks done"). Tapping a day opens its tasks or findings.

## 7. Deferred problems → manager alert
- When reporting a finding, the worker picks:
  - **Fixed now**: the finding is resolved;
  - **Can't fix now → schedule**: the worker picks a date/time and the finding becomes scheduled.
- Every 15 minutes the system looks for findings past their scheduled time that are still unresolved. For each one it notifies the plant's managers and the admins **once**.
- The **Findings** screen lists open, scheduled and overdue items with a Resolve action.

## Notifications
- **In-app:** the existing bell. It now also shows check reminders and overdue findings.
- **Push:** phone notifications via Firebase Cloud Messaging, even when the app is closed.
  - The app registers its device token at login.
  - A Supabase Edge Function (`send-push`) sends a push for every new notification.
- **Needed from the owner:**
  - a free Firebase project and its config files;
  - for iOS, an Apple developer account and APNs key (iOS builds require a Mac).

## Database changes (migration `20261108000001_checks_findings.sql`)

| Table | Purpose |
|---|---|
| `check_sheets` | One row per uploaded Excel file |
| `check_items` | Recurring check definitions (equipment, title, frequency, start date) |
| `check_tasks` | One row per due occurrence; status pending / done / missed |
| `findings` | Problems found; status open / scheduled / resolved; scheduled time; who fixed it |
| `device_tokens` | Phone push tokens per user |
| `notifications` (changed) | New kinds: `check_due`, `check_overdue`, `finding_overdue`; links to tasks and findings |

Security follows the existing plant-scoped rules:
- users only see their plants' checks and findings;
- only managers/admins can upload sheets or edit check items;
- workers can only tick tasks and report or resolve findings;
- changes are written to the audit log.

## Build order
1. Equipment codes + QR scan
2. Excel import + check sheets screen
3. My checks (worker)
4. Findings + deferral
5. Scheduled jobs (task generation, reminders, overdue alerts)
6. Graphs
7. Push notifications

## How it will be tested
- **Unit tests:**
  - Excel parsing/validation;
  - recurrence dates (weekly 1 → 8 → 15; monthly 7 Nov → 7 Dec; 31 Jan → end of Feb).
- **Database checks:**
  - no duplicate tasks when generation runs twice;
  - plant isolation;
  - workers cannot edit check items;
  - one overdue alert per deferred finding.
- **End-to-end on Android and web:**
  1. Upload a sheet.
  2. The worker ticks checks, reports a problem and defers it.
  3. The manager receives the alert.
  4. The graphs show the right numbers.
  5. Scanning a QR opens the right equipment.
