import Link from "next/link";
import { getVisiblePlants, requireUser } from "@/lib/auth";
import { StatusBadge, timeAgo } from "@/components/status-badge";
import type { CurrentStatusRow, StatusType } from "@/lib/types";

const PAGE_SIZE = 25;

export default async function EquipmentList(props: PageProps<"/equipment">) {
  const sp = await props.searchParams;
  const q = typeof sp.q === "string" ? sp.q.trim() : "";
  const plant = typeof sp.plant === "string" ? sp.plant : "";
  const status = typeof sp.status === "string" ? sp.status : "";
  const page = Math.max(1, Number(typeof sp.page === "string" ? sp.page : 1) || 1);

  const { supabase } = await requireUser();
  const [plants, { data: types }] = await Promise.all([
    getVisiblePlants(),
    supabase.from("status_types").select("id,key,label,color,is_failure,sort_order").eq("active", true).order("sort_order"),
  ]);
  const statusTypes = (types ?? []) as StatusType[];
  const typeById = new Map(statusTypes.map((t) => [t.id, t]));
  const plantById = new Map(plants.map((p) => [p.id, p]));

  let query = supabase
    .from("equipment_current_status")
    .select("*", { count: "exact" })
    .order("name")
    .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1);
  if (q) query = query.or(`name.ilike.%${q.replace(/[%,()]/g, " ")}%,tag_code.ilike.%${q.replace(/[%,()]/g, " ")}%`);
  if (plant) query = query.eq("plant_id", plant);
  if (status === "none") query = query.is("status_type_id", null);
  else if (status) query = query.eq("status_type_id", status);

  const { data, count } = await query;
  const rows = (data ?? []) as CurrentStatusRow[];
  const pages = Math.max(1, Math.ceil((count ?? 0) / PAGE_SIZE));
  const qs = (p: number) => {
    const u = new URLSearchParams();
    if (q) u.set("q", q);
    if (plant) u.set("plant", plant);
    if (status) u.set("status", status);
    u.set("page", String(p));
    return `?${u}`;
  };

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-bold">Equipment</h1>
      <form className="flex flex-wrap gap-2">
        <input name="q" defaultValue={q} placeholder="Search name or tag" className="min-w-40 flex-1 rounded border px-3 py-2" />
        {plants.length > 1 && (
          <select name="plant" defaultValue={plant} className="rounded border px-2 py-2">
            <option value="">All plants</option>
            {plants.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        )}
        <select name="status" defaultValue={status} className="rounded border px-2 py-2">
          <option value="">Any status</option>
          {statusTypes.map((t) => <option key={t.id} value={t.id}>{t.label}</option>)}
          <option value="none">No status yet</option>
        </select>
        <button className="rounded bg-blue-600 px-4 py-2 text-white">Filter</button>
      </form>

      {rows.length === 0 && <p className="text-gray-500">No equipment found. {plants.length === 0 && "You are not assigned to any plant yet."}</p>}
      <ul className="flex flex-col gap-2">
        {rows.map((r) => (
          <li key={r.equipment_id} className="flex items-center justify-between gap-3 rounded-lg border p-3">
            <Link href={`/equipment/${r.equipment_id}`} className="min-w-0 flex-1">
              <div className="truncate font-semibold">{r.name}</div>
              <div className="text-xs text-gray-500">
                {r.tag_code} · {plantById.get(r.plant_id)?.name} · updated {timeAgo(r.reported_at)}
              </div>
            </Link>
            <StatusBadge status={r.status_type_id ? typeById.get(r.status_type_id) : null} />
            <Link href={`/equipment/${r.equipment_id}/update`} className="rounded-lg bg-blue-600 px-3 py-2 text-sm font-semibold text-white">
              Report
            </Link>
          </li>
        ))}
      </ul>

      <div className="flex items-center justify-between text-sm">
        {page > 1 ? <Link href={qs(page - 1)}>← Previous</Link> : <span />}
        <span className="text-gray-500">Page {page} of {pages}</span>
        {page < pages ? <Link href={qs(page + 1)}>Next →</Link> : <span />}
      </div>
    </div>
  );
}
