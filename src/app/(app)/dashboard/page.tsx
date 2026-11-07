import Link from "next/link";
import { Suspense } from "react";
import { Activity, AlertTriangle, ArrowRight, CheckCircle2, CircleHelp, Gauge, PartyPopper, Wrench, type LucideIcon } from "lucide-react";
import { getVisiblePlants, requireRole } from "@/lib/auth";
import { StatusBadge, formatDateTime, timeAgo } from "@/components/status-badge";
import LiveRefresh from "@/components/live-refresh";
import PlantFilter from "@/components/plant-filter";
import { StatusBar, StatusLegend, type Segment } from "@/components/status-bar";
import { Card, CardHeader, EmptyState, PageHeader, Table, tdClass, thClass } from "@/components/ui";
import type { CurrentStatusRow, StatusType } from "@/lib/types";

function Kpi({ label, value, hint, icon: Icon, tone }: { label: string; value: string | number; hint?: string; icon: LucideIcon; tone: "primary" | "success" | "danger" | "muted" }) {
  const tones = {
    primary: "bg-primary-soft text-primary",
    success: "bg-success/10 text-success",
    danger: "bg-danger-soft text-danger",
    muted: "bg-surface-muted text-muted",
  };
  return (
    <Card className="p-5">
      <div className="flex items-start justify-between">
        <p className="text-sm font-medium text-muted">{label}</p>
        <span className={`flex size-8 items-center justify-center rounded-lg ${tones[tone]}`}>
          <Icon className="size-4" />
        </span>
      </div>
      <p className="mt-2 text-3xl font-semibold tracking-tight tabular-nums">{value}</p>
      {hint && <p className="mt-1 text-xs text-muted">{hint}</p>}
    </Card>
  );
}

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
    .limit(12);
  if (plantFilter) {
    cur = cur.eq("plant_id", plantFilter);
    ev = ev.eq("plant_id", plantFilter);
  }
  const [{ data: current }, { data: recent }] = await Promise.all([cur, ev]);
  const rows = (current ?? []) as CurrentStatusRow[];

  const segmentsFor = (list: CurrentStatusRow[]): Segment[] => {
    const counts = new Map<string, number>();
    let none = 0;
    for (const r of list) {
      if (!r.status_type_id) none++;
      else counts.set(r.status_type_id, (counts.get(r.status_type_id) ?? 0) + 1);
    }
    return [...statusTypes.map((t) => ({ status: t, count: counts.get(t.id) ?? 0 })), { status: null, count: none }];
  };
  const segments = segmentsFor(rows);

  const failing = rows
    .filter((r) => r.status_type_id && typeById.get(r.status_type_id)?.is_failure)
    .sort((a, b) => (a.reported_at ?? "").localeCompare(b.reported_at ?? ""));
  const unknown = rows.filter((r) => !r.status_type_id).length;
  const operational = rows.length - failing.length - unknown;
  const availability = rows.length ? Math.round((operational / rows.length) * 100) : 0;

  const plantRows = plantFilter
    ? []
    : plants
        .map((p) => {
          const list = rows.filter((r) => r.plant_id === p.id);
          return { plant: p, total: list.length, down: list.filter((r) => r.status_type_id && typeById.get(r.status_type_id)?.is_failure).length, segments: segmentsFor(list) };
        })
        .filter((p) => p.total > 0)
        .sort((a, b) => b.down - a.down);

  type Recent = {
    id: string; equipment_id: string; status_type_id: string; note: string | null; reported_at: string;
    plant_id: string; equipment: { name: string } | null; profiles: { name: string } | null;
  };
  const recentRows = (recent ?? []) as unknown as Recent[];
  const withPlant = (href: string) => `${href}${plantFilter ? `&plant=${plantFilter}` : ""}`;

  return (
    <div className="flex flex-col gap-6">
      <LiveRefresh />
      <PageHeader
        title="Dashboard"
        description={plantFilter ? `Live status for ${plantById.get(plantFilter)?.name ?? "selected plant"}` : "Live equipment status across your plants"}
        actions={plants.length > 1 && <Suspense><PlantFilter plants={plants} /></Suspense>}
      />

      <section className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Kpi label="Total equipment" value={rows.length} hint={`${plantFilter ? 1 : plants.length} plant${plants.length === 1 || plantFilter ? "" : "s"}`} icon={Wrench} tone="primary" />
        <Kpi label="Availability" value={`${availability}%`} hint={`${operational} operational`} icon={Gauge} tone="success" />
        <Kpi label="Down / failing" value={failing.length} hint={failing.length ? `Oldest ${timeAgo(failing[0].reported_at)}` : "All clear"} icon={AlertTriangle} tone="danger" />
        <Kpi label="No status yet" value={unknown} hint="Never reported" icon={CircleHelp} tone="muted" />
      </section>

      <div className="grid gap-6 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader title="Status distribution" description="Click a status to see that equipment" />
          <div className="flex flex-col gap-5 p-5">
            <StatusBar segments={segments} height="h-4" label="Status distribution" />
            <StatusLegend segments={segments} hrefFor={(s) => withPlant(`/equipment?status=${s.status?.id ?? "none"}`)} />
          </div>
        </Card>

        <Card>
          <CardHeader title="By plant" description={plantFilter ? "Filtered to one plant" : "Sorted by equipment down"} />
          {plantFilter || plantRows.length === 0 ? (
            <p className="p-5 text-sm text-muted">{plantFilter ? "Clear the plant filter to compare plants." : "No equipment yet."}</p>
          ) : (
            <ul className="divide-y">
              {plantRows.map((p) => (
                <li key={p.plant.id}>
                  <Link href={`/dashboard?plant=${p.plant.id}`} className="block px-5 py-3 hover:bg-surface-muted">
                    <div className="mb-2 flex items-center justify-between text-sm">
                      <span className="font-medium">{p.plant.name}</span>
                      <span className="text-xs text-muted">
                        {p.down > 0 ? <span className="font-medium text-danger">{p.down} down</span> : "All up"} · {p.total}
                      </span>
                    </div>
                    <StatusBar segments={p.segments} height="h-2" label={p.plant.name} />
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <Card className="overflow-hidden lg:col-span-2">
          <CardHeader
            title={<span className="flex items-center gap-2">Needs attention <span className="rounded-full bg-danger-soft px-2 py-0.5 text-xs font-medium text-danger">{failing.length}</span></span>}
            description="Failing equipment, longest-down first"
          />
          {failing.length === 0 ? (
            <EmptyState icon={PartyPopper} title="Nothing is down right now" description="All reported equipment is operational." />
          ) : (
            <Table>
              <thead>
                <tr>
                  <th className={thClass}>Equipment</th>
                  <th className={`${thClass} hidden sm:table-cell`}>Plant</th>
                  <th className={thClass}>Status</th>
                  <th className={`${thClass} text-right`}>Down for</th>
                </tr>
              </thead>
              <tbody>
                {failing.slice(0, 10).map((r) => (
                  <tr key={r.equipment_id} className="hover:bg-surface-muted/60">
                    <td className={tdClass}>
                      <Link href={`/equipment/${r.equipment_id}`} className="font-medium hover:text-primary">{r.name}</Link>
                      <div className="max-w-xs truncate text-xs text-muted">{r.tag_code}{r.note ? ` · ${r.note}` : ""}</div>
                    </td>
                    <td className={`${tdClass} hidden text-muted sm:table-cell`}>{plantById.get(r.plant_id)?.name}</td>
                    <td className={tdClass}><StatusBadge status={typeById.get(r.status_type_id!)} /></td>
                    <td className={`${tdClass} text-right tabular-nums text-muted`}>{timeAgo(r.reported_at)}</td>
                  </tr>
                ))}
              </tbody>
            </Table>
          )}
          {failing.length > 10 && (
            <Link href={withPlant(`/equipment?status=failing`)} className="block px-5 py-3 text-sm font-medium text-primary hover:underline">
              View all {failing.length}
            </Link>
          )}
        </Card>

        <Card>
          <CardHeader
            title="Recent activity"
            action={<Link href="/history" className="flex items-center gap-1 text-xs font-medium text-primary hover:underline">Full history <ArrowRight className="size-3" /></Link>}
          />
          {recentRows.length === 0 ? (
            <EmptyState icon={Activity} title="No reports yet" />
          ) : (
            <ol className="relative px-5 py-4">
              <span className="absolute bottom-6 left-[27px] top-6 w-px bg-border" aria-hidden />
              {recentRows.map((e) => {
                const t = typeById.get(e.status_type_id);
                return (
                  <li key={e.id} className="relative flex gap-3 pb-4 last:pb-0">
                    <span className="relative z-10 mt-1 flex size-3 shrink-0 items-center justify-center rounded-full bg-surface ring-2 ring-surface">
                      <span className="size-2.5 rounded-full" style={{ backgroundColor: t?.color ?? "var(--muted)" }} />
                    </span>
                    <Link href={`/equipment/${e.equipment_id}`} className="min-w-0 flex-1 hover:text-primary">
                      <p className="truncate text-sm font-medium">{e.equipment?.name}</p>
                      <p className="text-xs text-muted">
                        {t?.label ?? "Status"} · {e.profiles?.name ?? "Unknown"}
                      </p>
                      <p className="text-[11px] text-muted" title={formatDateTime(e.reported_at, plantById.get(e.plant_id)?.timezone)}>{timeAgo(e.reported_at)}</p>
                    </Link>
                  </li>
                );
              })}
            </ol>
          )}
        </Card>
      </div>

      {operational === rows.length && rows.length > 0 && (
        <p className="flex items-center gap-2 text-sm text-success"><CheckCircle2 className="size-4" /> Every piece of equipment is operational.</p>
      )}
    </div>
  );
}
