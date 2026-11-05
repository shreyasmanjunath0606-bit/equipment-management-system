import Link from "next/link";
import { getVisiblePlants, requireRole } from "@/lib/auth";
import { StatusBadge, formatDateTime, timeAgo } from "@/components/status-badge";
import LiveRefresh from "@/components/live-refresh";
import type { CurrentStatusRow, StatusType } from "@/lib/types";

export default async function Dashboard(props: PageProps<"/dashboard">) {
  const sp = await props.searchParams;
  const plantFilter = typeof sp.plant === "string" ? sp.plant : "";
  const { supabase } = await requireRole("manager", "admin");

  const [plants, { data: types }] = await Promise.all([
    getVisiblePlants(),
    supabase.from("status_types").select("id,key,label,color,is_failure,sort_order").eq("active", true).order("sort_order"),
  ]);
  const statusTypes = (types ?? []) as StatusType[];
  const typeById = new Map(statusTypes.map((t) => [t.id, t]));
  const plantById = new Map(plants.map((p) => [p.id, p]));

  let cur = supabase.from("equipment_current_status").select("*").limit(5000);
  let ev = supabase
    .from("status_events")
    .select("id,equipment_id,status_type_id,note,reported_at,plant_id,equipment(name),profiles(name)")
    .order("reported_at", { ascending: false })
    .limit(15);
  if (plantFilter) {
    cur = cur.eq("plant_id", plantFilter);
    ev = ev.eq("plant_id", plantFilter);
  }
  const [{ data: current }, { data: recent }] = await Promise.all([cur, ev]);
  const rows = (current ?? []) as CurrentStatusRow[];

  const counts = new Map<string, number>();
  let none = 0;
  for (const r of rows) {
    if (!r.status_type_id) none++;
    else counts.set(r.status_type_id, (counts.get(r.status_type_id) ?? 0) + 1);
  }
  const failing = rows
    .filter((r) => r.status_type_id && typeById.get(r.status_type_id)?.is_failure)
    .sort((a, b) => (a.reported_at ?? "").localeCompare(b.reported_at ?? ""));

  type Recent = {
    id: string; equipment_id: string; status_type_id: string; note: string | null; reported_at: string;
    plant_id: string; equipment: { name: string } | null; profiles: { name: string } | null;
  };
  const recentRows = (recent ?? []) as unknown as Recent[];

  return (
    <div className="flex flex-col gap-6">
      <LiveRefresh />
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-xl font-bold">Dashboard</h1>
        {plants.length > 1 && (
          <form className="flex gap-2">
            <select name="plant" defaultValue={plantFilter} className="rounded border px-2 py-1">
              <option value="">All plants</option>
              {plants.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
            <button className="rounded border px-3 py-1">Apply</button>
          </form>
        )}
      </div>

      <section className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {statusTypes.map((t) => (
          <Link key={t.id} href={`/equipment?status=${t.id}${plantFilter ? `&plant=${plantFilter}` : ""}`}
            className="rounded-xl p-4 text-white" style={{ backgroundColor: t.color }}>
            <div className="text-3xl font-bold">{counts.get(t.id) ?? 0}</div>
            <div className="text-sm">{t.label}</div>
          </Link>
        ))}
        <Link href={`/equipment?status=none${plantFilter ? `&plant=${plantFilter}` : ""}`} className="rounded-xl bg-gray-200 p-4 text-gray-800">
          <div className="text-3xl font-bold">{none}</div>
          <div className="text-sm">No status yet</div>
        </Link>
      </section>

      <section>
        <h2 className="mb-2 font-semibold">Needs attention ({failing.length})</h2>
        {failing.length === 0 && <p className="text-sm text-gray-500">Nothing is down right now. 🎉</p>}
        <ul className="flex flex-col gap-2">
          {failing.map((r) => (
            <li key={r.equipment_id} className="flex items-center justify-between gap-3 rounded-lg border border-red-300 p-3">
              <Link href={`/equipment/${r.equipment_id}`} className="min-w-0 flex-1">
                <div className="truncate font-semibold">{r.name}</div>
                <div className="text-xs text-gray-500">
                  {plantById.get(r.plant_id)?.name} · since {timeAgo(r.reported_at)}
                  {r.note ? ` · ${r.note}` : ""}
                </div>
              </Link>
              <StatusBadge status={typeById.get(r.status_type_id!)} />
            </li>
          ))}
        </ul>
      </section>

      <section>
        <h2 className="mb-2 font-semibold">Recent activity</h2>
        <ul className="flex flex-col gap-2">
          {recentRows.map((e) => (
            <li key={e.id} className="rounded-lg border p-3 text-sm">
              <Link href={`/equipment/${e.equipment_id}`} className="flex flex-wrap items-center gap-2">
                <StatusBadge status={typeById.get(e.status_type_id)} />
                <strong>{e.equipment?.name}</strong>
                <span className="text-gray-500">
                  {formatDateTime(e.reported_at, plantById.get(e.plant_id)?.timezone)} · {e.profiles?.name}
                </span>
              </Link>
            </li>
          ))}
        </ul>
        <Link href="/history" className="mt-2 inline-block text-sm text-blue-600">Full history →</Link>
      </section>
    </div>
  );
}
