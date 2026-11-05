import Link from "next/link";
import { getVisiblePlants, requireUser } from "@/lib/auth";
import { StatusBadge, formatDateTime } from "@/components/status-badge";
import { historyQuery, parseFilters } from "@/lib/history-query";
import type { StatusType } from "@/lib/types";

const PAGE_SIZE = 50;

export default async function HistoryPage(props: PageProps<"/history">) {
  const sp = await props.searchParams;
  const f = parseFilters(sp);
  const page = Math.max(1, Number(typeof sp.page === "string" ? sp.page : 1) || 1);
  const { supabase, profile } = await requireUser();

  const [plants, { data: types }] = await Promise.all([
    getVisiblePlants(),
    supabase.from("status_types").select("id,key,label,color,is_failure,sort_order").order("sort_order"),
  ]);
  const statusTypes = (types ?? []) as StatusType[];
  const typeById = new Map(statusTypes.map((t) => [t.id, t]));
  const plantById = new Map(plants.map((p) => [p.id, p]));

  const { data, count } = await historyQuery(
    supabase, f, "id,equipment_id,plant_id,status_type_id,note,reported_at,equipment(name,tag_code),profiles(name)", true,
  ).range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1);

  type Row = {
    id: string; equipment_id: string; plant_id: string; status_type_id: string; note: string | null; reported_at: string;
    equipment: { name: string; tag_code: string } | null; profiles: { name: string } | null;
  };
  const rows = (data ?? []) as unknown as Row[];
  const pages = Math.max(1, Math.ceil((count ?? 0) / PAGE_SIZE));

  const base = new URLSearchParams();
  (Object.entries(f) as [string, string][]).forEach(([k, v]) => v && base.set(k, v));
  const link = (p: number) => `?${new URLSearchParams({ ...Object.fromEntries(base), page: String(p) })}`;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-bold">History</h1>
        {profile.role !== "worker" && (
          <a href={`/history/export?${base}`} className="rounded border px-3 py-1 text-sm">Export CSV</a>
        )}
      </div>
      <form className="flex flex-wrap items-end gap-2 text-sm">
        <label className="flex flex-col">From<input type="date" name="from" defaultValue={f.from} className="rounded border px-2 py-1" /></label>
        <label className="flex flex-col">To<input type="date" name="to" defaultValue={f.to} className="rounded border px-2 py-1" /></label>
        {plants.length > 1 && (
          <select name="plant" defaultValue={f.plant} className="rounded border px-2 py-1.5">
            <option value="">All plants</option>
            {plants.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        )}
        <select name="status" defaultValue={f.status} className="rounded border px-2 py-1.5">
          <option value="">Any status</option>
          {statusTypes.map((t) => <option key={t.id} value={t.id}>{t.label}</option>)}
        </select>
        <button className="rounded bg-blue-600 px-4 py-1.5 text-white">Apply</button>
      </form>

      <p className="text-sm text-gray-500">{count ?? 0} report(s)</p>
      <ul className="flex flex-col gap-2">
        {rows.map((r) => (
          <li key={r.id} className="rounded-lg border p-3 text-sm">
            <Link href={`/equipment/${r.equipment_id}`} className="flex flex-wrap items-center gap-2">
              <StatusBadge status={typeById.get(r.status_type_id)} />
              <strong>{r.equipment?.name}</strong>
              <span className="text-gray-500">{r.equipment?.tag_code} · {plantById.get(r.plant_id)?.name}</span>
            </Link>
            <div className="text-xs text-gray-500">
              {formatDateTime(r.reported_at, plantById.get(r.plant_id)?.timezone)} · {r.profiles?.name}
            </div>
            {r.note && <p className="mt-1 whitespace-pre-wrap">{r.note}</p>}
          </li>
        ))}
      </ul>
      <div className="flex items-center justify-between text-sm">
        {page > 1 ? <Link href={link(page - 1)}>← Newer</Link> : <span />}
        <span className="text-gray-500">Page {page} of {pages}</span>
        {page < pages ? <Link href={link(page + 1)}>Older →</Link> : <span />}
      </div>
    </div>
  );
}
