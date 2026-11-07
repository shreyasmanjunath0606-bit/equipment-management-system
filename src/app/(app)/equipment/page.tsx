import Link from "next/link";
import { ChevronLeft, ChevronRight, ClipboardEdit, Search, Wrench, X } from "lucide-react";
import { getVisiblePlants, requireUser } from "@/lib/auth";
import { StatusBadge, timeAgo } from "@/components/status-badge";
import { Card, EmptyState, Input, PageHeader, Select, Table, buttonClass, tdClass, thClass } from "@/components/ui";
import AutoSubmit from "@/components/auto-submit";
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
  else if (status === "failing") query = query.in("status_type_id", statusTypes.filter((t) => t.is_failure).map((t) => t.id));
  else if (status) query = query.eq("status_type_id", status);

  const { data, count } = await query;
  const rows = (data ?? []) as CurrentStatusRow[];
  const total = count ?? 0;
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const qs = (over: Record<string, string | null>) => {
    const u = new URLSearchParams();
    const cur: Record<string, string> = { q, plant, status, page: String(page) };
    for (const [k, v] of Object.entries({ ...cur, ...over })) if (v && !(k === "page" && v === "1")) u.set(k, v);
    return `?${u}`;
  };

  const statusLabel =
    status === "none" ? "No status yet" : status === "failing" ? "Failing" : typeById.get(status)?.label;
  const chips = [
    q && { label: `"${q}"`, href: qs({ q: null, page: null }) },
    plant && { label: plantById.get(plant)?.name ?? "Plant", href: qs({ plant: null, page: null }) },
    status && { label: statusLabel ?? "Status", href: qs({ status: null, page: null }) },
  ].filter(Boolean) as { label: string; href: string }[];

  const from = total ? (page - 1) * PAGE_SIZE + 1 : 0;
  const to = Math.min(page * PAGE_SIZE, total);

  return (
    <div>
      <PageHeader title="Equipment" description="Find a machine and report its current status." />

      <Card className="overflow-hidden">
        {/* Toolbar */}
        <form className="flex flex-col gap-3 border-b p-4 sm:flex-row sm:items-center">
          <AutoSubmit />
          <div className="relative flex-1">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted" />
            <Input name="q" defaultValue={q} placeholder="Search by name or tag…" className="pl-9" aria-label="Search equipment" />
          </div>
          {plants.length > 1 && (
            <Select name="plant" defaultValue={plant} aria-label="Plant" className="sm:w-44">
              <option value="">All plants</option>
              {plants.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </Select>
          )}
          <Select name="status" defaultValue={status} aria-label="Status" className="sm:w-44">
            <option value="">Any status</option>
            <option value="failing">Failing (any)</option>
            {statusTypes.map((t) => <option key={t.id} value={t.id}>{t.label}</option>)}
            <option value="none">No status yet</option>
          </Select>
          <noscript><button className={buttonClass()}>Filter</button></noscript>
        </form>

        {chips.length > 0 && (
          <div className="flex flex-wrap items-center gap-2 border-b bg-surface-muted/40 px-4 py-2.5">
            <span className="text-xs text-muted">{total} result{total === 1 ? "" : "s"} for</span>
            {chips.map((c) => (
              <Link key={c.label} href={c.href} className="inline-flex items-center gap-1 rounded-full border bg-surface px-2.5 py-0.5 text-xs font-medium hover:border-primary">
                {c.label} <X className="size-3" />
              </Link>
            ))}
            <Link href="/equipment" className="text-xs font-medium text-primary hover:underline">Clear all</Link>
          </div>
        )}

        {rows.length === 0 ? (
          <EmptyState
            icon={Wrench}
            title="No equipment found"
            description={plants.length === 0 ? "You are not assigned to any plant yet. Ask an administrator for access." : "Try a different search or clear the filters."}
            action={chips.length > 0 && <Link href="/equipment" className={buttonClass("secondary")}>Clear filters</Link>}
          />
        ) : (
          <>
            {/* Desktop table */}
            <div className="hidden md:block">
              <Table>
                <thead>
                  <tr>
                    <th className={thClass}>Equipment</th>
                    <th className={thClass}>Tag</th>
                    {plants.length > 1 && <th className={thClass}>Plant</th>}
                    <th className={thClass}>Status</th>
                    <th className={thClass}>Last update</th>
                    <th className={`${thClass} text-right`}><span className="sr-only">Actions</span></th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.equipment_id} className="group hover:bg-surface-muted/60">
                      <td className={tdClass}>
                        <Link href={`/equipment/${r.equipment_id}`} className="font-medium hover:text-primary">{r.name}</Link>
                        {r.type && <div className="text-xs text-muted">{r.type}</div>}
                      </td>
                      <td className={`${tdClass} font-mono text-xs text-muted`}>{r.tag_code}</td>
                      {plants.length > 1 && <td className={`${tdClass} text-muted`}>{plantById.get(r.plant_id)?.name}</td>}
                      <td className={tdClass}><StatusBadge status={r.status_type_id ? typeById.get(r.status_type_id) : null} /></td>
                      <td className={`${tdClass} text-muted`}>{timeAgo(r.reported_at)}</td>
                      <td className={`${tdClass} text-right`}>
                        <Link href={`/equipment/${r.equipment_id}/update`} className={buttonClass("secondary", "sm")}>
                          <ClipboardEdit className="size-3.5" /> Report
                        </Link>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </Table>
            </div>

            {/* Mobile cards */}
            <ul className="divide-y md:hidden">
              {rows.map((r) => (
                <li key={r.equipment_id} className="flex items-center gap-3 p-4">
                  <Link href={`/equipment/${r.equipment_id}`} className="min-w-0 flex-1">
                    <p className="truncate font-medium">{r.name}</p>
                    <p className="mt-0.5 truncate text-xs text-muted">
                      <span className="font-mono">{r.tag_code}</span> · {plantById.get(r.plant_id)?.name} · {timeAgo(r.reported_at)}
                    </p>
                    <StatusBadge className="mt-2" status={r.status_type_id ? typeById.get(r.status_type_id) : null} />
                  </Link>
                  <Link href={`/equipment/${r.equipment_id}/update`} className={buttonClass("primary", "md")} aria-label={`Report status for ${r.name}`}>
                    <ClipboardEdit className="size-4" /> Report
                  </Link>
                </li>
              ))}
            </ul>
          </>
        )}

        {/* Pagination */}
        {total > 0 && (
          <div className="flex items-center justify-between gap-3 border-t px-4 py-3 text-sm">
            <span className="text-muted">
              Showing <span className="font-medium text-foreground">{from}–{to}</span> of <span className="font-medium text-foreground">{total}</span>
            </span>
            <div className="flex items-center gap-2">
              {page > 1 ? (
                <Link href={qs({ page: String(page - 1) })} className={buttonClass("secondary", "sm")} aria-label="Previous page"><ChevronLeft className="size-4" /></Link>
              ) : (
                <span className={buttonClass("secondary", "sm", "pointer-events-none opacity-40")} aria-hidden><ChevronLeft className="size-4" /></span>
              )}
              <span className="tabular-nums text-muted">{page} / {pages}</span>
              {page < pages ? (
                <Link href={qs({ page: String(page + 1) })} className={buttonClass("secondary", "sm")} aria-label="Next page"><ChevronRight className="size-4" /></Link>
              ) : (
                <span className={buttonClass("secondary", "sm", "pointer-events-none opacity-40")} aria-hidden><ChevronRight className="size-4" /></span>
              )}
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}
