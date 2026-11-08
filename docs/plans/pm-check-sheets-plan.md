# PM check-sheet import (ALP C GUN format)

## Context
The app today only imports a flat template (one row = equipment code + check item + Daily/Weekly/Monthly), see
`flutter_app/lib/data/excel_sheets.dart`. The plant's real check sheets look like `ALP C GUN.xlsx`: one workbook per
equipment, one tab per PM check, rich per-point instructions and pictures. The admin should upload that workbook as-is;
the app must read the frequency from the sheet itself (no manual choice) and give workers every detail on the sheet.

## What the workbook contains (verified on all 18 tabs)
Every tab uses the same template:

| Where | Content | Example |
|---|---|---|
| A1 (merged A1:V1) | Check title | `AIR LEAK CHECK` |
| B2 → C2 | Equipment / gun no. | `EQUIPMENT PSW ALP GUN NO:` → `C` |
| E2 → F2 | Equipment PM rank | `B` |
| **G2 → G3** | **FREQUENCY** | `MONTHLY`, `4 MONTHLY`, `HALF YEARLY` |
| H2 → H3 | PM type | `ONLINE` / `OFFLINE` |
| I2 → I3 | Man power | `1`, or `SHI: 2\nSPC: 1` |
| J2 → J3 | Time (min) | `17`, or `SHI: 8\nSPC: 15` |
| B3 | Kanban no. | (blank in this file) |
| F4 (merged F4:J4) | Sheet-wide safety warning | `REMOVE THE CONCENTRIC PLUG BEFORE WORKING ON GUN` |
| K4 (merged K4:V4) | Plan start date (Excel serial) | 46327 = 1 Nov 2026 |
| K2–V3 | Result legend (shapes) | ○ OK · △ Abnormal pending · ⊗ Immediate correction · ▲ Pending completed |
| Row 5 | Column headers | SAFETY POINT, KEY POINTS, IF PM NOT DONE, CHECKING METHOD, CHECK POINT, STD VALUE, ACTION IF NG, PM RANK |
| Rows 6..n | Check points: A=SL no, B=check point text, C..J = the headers above (G = picture) | 3–9 points per tab |
| Footer | `TOOLS:` text (col A) + `OBARA TM SIGN & DATE`, `OBARA INCHARGE SIGN & DATE` | |
| Drawings | Pictures anchored in col G (sometimes F:G), spanning one or several point rows; 30 are `.tmp` (really JPEG), 1 EMF | |

Frequencies in this file: 9 tabs MONTHLY, 5 tabs 4 MONTHLY, 4 tabs HALF YEARLY. **Daily and weekly check sheets use
exactly the same layout** (only G3 differs: `DAILY` / `WEEKLY`), so one parser handles all of them, and a workbook may
mix daily, weekly and monthly tabs. Tab names also carry a hint (`-1D`, `-1W`, `-1M`, `4M`, `6M`) used only as a fallback.

## Schedule generated per frequency (all automatic, read from the sheet)
Start = date in the header (K4), else upload date. Every plan is generated the same way by `generate_check_tasks`
(cron, hourly, 7 days ahead, idempotent), and every task is a full check with all its points.

| Frequency cell | Due on | Can be completed until | Shows to worker |
|---|---|---|---|
| `DAILY` | every day from start | same day (then Missed) | Today |
| `WEEKLY` | every 7 days from start (same weekday) | 6 days after due | Today on due day, then Overdue until window ends; reminder the day before |
| `MONTHLY` | same day-of-month each month | day before next month's due | same as weekly |
| `N MONTHLY` / `QUARTERLY` / `HALF YEARLY` / `YEARLY` | every N months | day before next due | same as weekly |

Daily/weekly use the existing `daily`/`weekly` units (interval 1); also accepted: `EVERY DAY`, `DAY`, `EVERY WEEK`,
`WEEK`, `1W`, `1D`, `2 WEEKLY`/`FORTNIGHTLY` (weekly×2). Anything else (e.g. `TWICE A WEEK`, `SHIFT`) is flagged on
the review page and not imported, never guessed.

## Approach

### 1. Data model (new migration `supabase/migrations/20261109000001_pm_check_sheets.sql`)
Mapping: **workbook → `check_sheets`**, **tab → `check_items`** (one PM check, has the frequency), **row → `check_points`** (new).
- `check_items`: add `interval_count int not null default 1` (4 MONTHLY = monthly×4, HALF YEARLY = monthly×6,
  YEARLY = monthly×12, TWICE A WEEK etc. rejected with a clear error), plus `pm_type`, `pm_rank`, `man_power text`,
  `time_minutes text`, `safety_note`, `tools`, `kanban_no`, `source_tab`.
- Update `check_due_on` / `check_window_end` to take `interval_count` (window = until the day before next occurrence).
  `generate_check_tasks` passes it through; existing rows default to 1 so nothing changes for them.
- New `check_points` (item_id, position, sl_no, check_point, safety_point, key_points, if_not_done, checking_method,
  std_value, action_if_ng, pm_rank, image_paths text[]).
- New `check_point_results` (task_id, point_id, result enum `ok | abnormal_pending | corrected | pending_completed`,
  reading/note, finding_id, unique(task_id, point_id)).
- RPC `submit_check_task(task_id, results jsonb)`: writes all point results (+ optional reading/remark), auto-creates
  a finding for each △ (linked via `finding_id`), marks the task done (only when every point has a result).
  When a △ finding is later resolved, the point shows as ▲ Pending completed (derived from finding status).
- In-charge sign-off: `check_tasks` gets `verified_by`, `verified_at`, `verify_note`; RPC `verify_check_task(task_id,
  note)` callable by plant managers/admins only, task must be `done`. Worker submission = "TM sign", verification =
  "Incharge sign". RLS + grants follow the existing patterns in
  `20261108000001_checks_findings.sql`.
- RPC `import_pm_workbook(p_plant, p_equipment, p_title, p_file_name, p_file_path, p_checks jsonb)` inserting
  sheet → items → points in one transaction, then `generate_check_tasks`.
- Storage: allow `image/jpeg`, `image/png` in bucket `check-sheets`; pictures stored at `<plant>/<sheet>/img/<n>.jpg`.
- Notification text in `notify_check_reminders` generalised ("4-monthly check" etc.).

### 2. Parser (`flutter_app/lib/data/pm_workbook.dart`, new)
Read the .xlsx directly with `archive` + `xml` (already transitive deps of `excel`; add them to `pubspec.yaml`),
because the `excel` package exposes neither drawings nor pictures and this file also has 31 external links.
- Load shared strings, workbook tab list, each sheet's cells + merged ranges (value of a merged range = top-left cell).
- **Detect the PM layout by labels, not fixed addresses**: find the cell whose text is `FREQUENCY` in the first 6
  rows → value is the cell below it; same for `PM TYPE`, `MAN POWER`, `TIME`; `EQUIPMENT PM RANK` / `GUN NO` /
  `KANBAN NO` → value to the right. Header row = the row containing `CHECKING METHOD` + `STD VALUE`; map each column by
  header text (aliases incl. typos seen: `KY POINTS`, `PM\nRANK`). Check-point column = the one labelled `PM CHECK POINTS`.
- Points = rows below the header with text in the check-point column; stop at `TOOLS`/`SIGN & DATE` rows.
  Rows with only a SL number (e.g. row 10 = `5`) are skipped.
- Frequency text → (unit, interval): DAILY, WEEKLY, MONTHLY, `N MONTHLY`, QUARTERLY, HALF YEARLY, YEARLY/ANNUAL;
  fallback to tab-name suffix (`1D/1W/1M/4M/6M`). Tabs where neither works are shown as errors, never guessed.
- Start date from the date cell in the header (K4); fallback = upload date.
- Pictures: parse `xl/drawings/drawingN.xml` + rels, take `pic` anchors (ignore the legend/highlight shapes), sniff
  bytes (JPEG/PNG; EMF skipped with a warning), attach each picture to every point whose row lies in the anchor's
  from–to row range.
- Workbooks without the PM layout fall back to the existing `parseCheckSheet` (flat template keeps working).
- Output: `PmWorkbook { title, equipmentRef, tabs: [PmCheck { title, frequency, interval, pmType, ..., points, problems }] }`.

### 3. Admin upload (`flutter_app/lib/features/admin/check_sheets_screen.dart`)
- Upload → parse → review page grouped by tab: title, detected frequency chip ("Monthly", "Every 4 months",
  "Every 6 months", "Daily", "Weekly"), PM type, man power/time, point count, picture count, problems.
  Frequency is read-only (taken from the sheet).
- Equipment link: auto-suggest by matching the gun no. (`C`) and file/title words (`ALP`, `GUN`) against plant
  equipment names and codes; admin confirms or changes it in a picker on the review page before importing.
- Import: upload pictures + original file to storage, call `import_pm_workbook`.
- Sheet card / items sheet shows tabs with their frequency and points.

### 4. Worker checklist (`flutter_app/lib/features/checks/my_checks_screen.dart` + new `check_run_screen.dart`)
- Tasks list stays grouped as today: Daily → Today; Weekly/Monthly/4-monthly/half-yearly show on their due day and
  stay in "Overdue" until their window ends. Chip shows the frequency.
- Tapping a PM task opens a run screen: header (title, equipment, PM type, man power, time, safety warning, tools)
  then one card per check point showing every column (check point, safety point, key points, checking method,
  std value, action if NG, if PM not done, PM rank, pictures with zoom) and result buttons ○ / ⊗ / △ (+ optional
  reading/note, photo for △). Submit enabled when all points answered; works offline via a new `QueuedKind.taskSubmit`
  in `offline_queue.dart`.
- Items without points (old flat template) keep the one-tap tick.
- In-charge verification: managers see an "Awaiting verification" list (done, unverified PM tasks) with the full
  result view and a Verify button (optional note). Task chips show Submitted / Verified.
- `CheckTask` in `data/checks.dart` gains `interval`, point count, PM metadata; completion export
  (`buildCompletionsReport`) adds per-point results.

## Verification
- Dart unit test `test/pm_workbook_test.dart` running the parser on `ALP C GUN.xlsx`: 18 tabs, frequencies
  9×monthly / 5×4-monthly / 4×half-yearly, point counts per tab (4,5,9,5,6,9,9,6,6,6,6,3,4,8,8,9,6,6), safety/tools text,
  start date 2026-11-01, pictures attached (e.g. tab 9 has 6 pictures on rows 6–11), EMF skipped.
- Same test on two in-memory variants of the workbook with G3 rewritten to `DAILY` and `WEEKLY` (built in the test
  from the real file's bytes): parsed as daily / weekly with identical points, pictures and metadata.
- SQL: daily item → a task every day; weekly item started 2026-11-01 → tasks on 11-01, 11-08, 11-15 with window +6.
- `flutter analyze` + `flutter test`.
- Apply migration to a Supabase branch; SQL checks: `check_due_on('monthly', 4, '2026-11-01', '2027-03-01')` = true,
  `... '2026-12-01'` = false; window ends.
- Run the web app: upload the workbook, review page shows all 18 tabs with correct frequency; log in as a worker,
  complete a monthly check with one △ → task done, finding created; untouched points block submit; log in as manager
  → task appears in Awaiting verification → verify; resolve the finding → point shows ▲.
