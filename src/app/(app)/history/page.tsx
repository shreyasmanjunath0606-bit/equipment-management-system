import Link from "next/link";
import { ChevronLeft, ChevronRight, Download, History } from "lucide-react";
import { getVisiblePlants, requireUser } from "@/lib/auth";
import { StatusBadge, formatDateTime } from "@/components/status-badge";
import { historyQuery, parseFilters } from "@/lib/history-query";
import { Card, EmptyState, Input, Label, PageHeader, Select, Table, buttonClass, tdClass, thClass } from "@/components/ui";
import AutoSubmit from "@/components/auto-submit";
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
  const total = count ?? 0;
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  const base = new URLSearchParams();
  (Object.entries(f) as [string, string][]).forEach(([k, v]) => v && base.set(k, v));
  const link = (p: number) => `?${new URLSearchParams({ ...Object.fromEntries(base), page: String(p) })}`;
  const from = total ? (page - 1) * PAGE_SIZE + 1 : 0;
  const to = Math.min(page * PAGE_SIZE, total);

  return (
    <div>
      <PageHeader
        title="History"
        description="Every status report, newest first."
        actions={profile.role !== "worker" && (
          <a href={`/history/export?${base}`} className={buttonClass("secondary")}><Download className="size-4" /> Export CSV</a>
        )}
      />

      <Card className="overflow-hidden">
        <form className="grid grid-cols-2 gap-3 border-b p-4 md:grid-cols-4">
          <AutoSubmit />
          <div><Label htmlFor="from">From</Label><Input id="from" type="date" name="from" defaultValue={f.from} /></div>
          <div><Label htmlFor="to">To</Label><Input id="to" type="date" name="to" defaultValue={f.to} /></div>
          {plants.length > 1 && (
            <div>
              <Label htmlFor="plant">Plant</Label>
              <Select id="plant" name="plant" defaultValue={f.plant}>
                <option value="">All plants</option>
                {plants.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
              </Select>
            </div>
          )}
          <div>
            <Label htmlFor="status">Status</Label>
            <Select id="status" name="status" defaultValue={f.status}>
              <option value="">Any status</option>
              {statusTypes.map((t) => <option key={t.id} value={t.id}>{t.label}</option>)}
            </Select>
          </div>
          <noscript><button className={buttonClass()}>Apply</button></noscript>
        </form>

        {rows.length === 0 ? (
          <EmptyState icon={History} title="No reports match" description="Try widening the date range or clearing filters." />
        ) : (
          <Table>
            <thead>
              <tr>
                <th className={thClass}>When</th>
                <th className={thClass}>Equipment</th>
                <th className={thClass}>Status</th>
                <th className={`${thClass} hidden md:table-cell`}>Reported by</th>
                <th className={`${thClass} hidden lg:table-cell`}>Note</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className="hover:bg-surface-muted/60">
                  <td className={`${tdClass} whitespace-nowrap text-muted`}>{formatDateTime(r.reported_at, plantById.get(r.plant_id)?.timezone)}</td>
                  <td className={tdClass}>
                    <Link href={`/equipment/${r.equipment_id}`} className="font-medium hover:text-primary">{r.equipment?.name}</Link>
                    <div className="text-xs text-muted"><span className="font-mono">{r.equipment?.tag_code}</span> · {plantById.get(r.plant_id)?.name}</div>
                  </td>
                  <td className={tdClass}><StatusBadge status={typeById.get(r.status_type_id)} /></td>
                  <td className={`${tdClass} hidden md:table-cell`}>{r.profiles?.name ?? "—"}</td>
                  <td className={`${tdClass} hidden max-w-xs truncate text-muted lg:table-cell`} title={r.note ?? undefined}>{r.note ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}

        {total > 0 && (
          <div className="flex items-center justify-between gap-3 border-t px-4 py-3 text-sm">
            <span className="text-muted">Showing <span className="font-medium text-foreground">{from}–{to}</span> of <span className="font-medium text-foreground">{total}</span></span>
            <div className="flex items-center gap-2">
              {page > 1 && <Link href={link(page - 1)} className={buttonClass("secondary", "sm")} aria-label="Newer"><ChevronLeft className="size-4" /></Link>}
              <span className="tabular-nums text-muted">{page} / {pages}</span>
              {page < pages && <Link href={link(page + 1)} className={buttonClass("secondary", "sm")} aria-label="Older"><ChevronRight className="size-4" /></Link>}
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}
