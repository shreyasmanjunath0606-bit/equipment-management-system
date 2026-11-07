import Link from "next/link";
import { notFound } from "next/navigation";
import { ChevronLeft, ChevronRight, ClipboardEdit, History, QrCode } from "lucide-react";
import { requireUser } from "@/lib/auth";
import { StatusBadge, formatDateTime, timeAgo } from "@/components/status-badge";
import PhotoLightbox from "@/components/photo-lightbox";
import { Card, CardHeader, EmptyState, Pill, buttonClass } from "@/components/ui";
import type { StatusEventRow, StatusType } from "@/lib/types";

const PAGE_SIZE = 50;

export default async function EquipmentDetail(props: PageProps<"/equipment/[id]">) {
  const { id } = await props.params;
  const sp = await props.searchParams;
  const page = Math.max(1, Number(typeof sp.page === "string" ? sp.page : 1) || 1);
  const { supabase, profile } = await requireUser();

  // RLS: returns nothing if the user has no access to this equipment's plant.
  const { data: eq } = await supabase
    .from("equipment")
    .select("id,tag_code,name,type,manufacturer,model,serial_no,install_date,is_active,plants(name,timezone),areas(name)")
    .eq("id", id)
    .maybeSingle();
  if (!eq) notFound();

  const [{ data: types }, { data: events, count }] = await Promise.all([
    supabase.from("status_types").select("id,key,label,color,is_failure,sort_order"),
    supabase
      .from("status_events")
      .select("id,equipment_id,status_type_id,note,photo_path,reported_by,reported_at,profiles(name)", { count: "exact" })
      .eq("equipment_id", id)
      .order("reported_at", { ascending: false })
      .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1),
  ]);
  const typeById = new Map(((types ?? []) as StatusType[]).map((t) => [t.id, t]));
  const rows = (events ?? []) as unknown as StatusEventRow[];

  const paths = rows.map((r) => r.photo_path).filter((p): p is string => !!p);
  const signed = paths.length
    ? (await supabase.storage.from("failure-photos").createSignedUrls(paths, 3600)).data ?? []
    : [];
  const photoUrl = new Map<string, string>();
  signed.forEach((s) => { if (s.path && s.signedUrl) photoUrl.set(s.path, s.signedUrl); });

  const plant = eq.plants as unknown as { name: string; timezone: string } | null;
  const area = eq.areas as unknown as { name: string } | null;
  const current = rows[0] && page === 1 ? typeById.get(rows[0].status_type_id) : undefined;
  const pages = Math.max(1, Math.ceil((count ?? 0) / PAGE_SIZE));

  const specs: [string, string | null | undefined][] = [
    ["Tag", eq.tag_code],
    ["Type", eq.type],
    ["Plant", plant?.name],
    ["Area", area?.name],
    ["Manufacturer", eq.manufacturer],
    ["Model", eq.model],
    ["Serial no.", eq.serial_no],
    ["Installed", eq.install_date ? new Date(eq.install_date).toLocaleDateString(undefined, { dateStyle: "medium" }) : null],
  ];

  return (
    <div className="flex flex-col gap-6">
      <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-xs text-muted">
        <Link href="/equipment" className="hover:text-foreground">Equipment</Link>
        <ChevronRight className="size-3" />
        <span className="truncate text-foreground">{eq.name}</span>
      </nav>

      {/* Header */}
      <Card className="p-5 sm:p-6">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="text-2xl font-semibold tracking-tight">{eq.name}</h1>
              {!eq.is_active && <Pill className="border-danger/30 bg-danger-soft text-danger">Retired</Pill>}
            </div>
            <p className="mt-1 text-sm text-muted">
              <span className="font-mono">{eq.tag_code}</span> · {plant?.name}{area ? ` · ${area.name}` : ""}
            </p>
            <div className="mt-3 flex items-center gap-2">
              <StatusBadge status={current} className="px-3 py-1 text-sm" />
              {rows[0] && page === 1 && <span className="text-xs text-muted">updated {timeAgo(rows[0].reported_at)} by {rows[0].profiles?.name ?? "unknown"}</span>}
            </div>
          </div>
          <div className="flex gap-2">
            {profile.role !== "worker" && (
              <Link href={`/equipment/${id}/qr`} className={buttonClass("secondary")}><QrCode className="size-4" /> QR code</Link>
            )}
            {eq.is_active && (
              <Link href={`/equipment/${id}/update`} className={buttonClass("primary")}><ClipboardEdit className="size-4" /> Report status</Link>
            )}
          </div>
        </div>
      </Card>

      <div className="grid gap-6 lg:grid-cols-3">
        {/* Specs */}
        <Card className="h-fit">
          <CardHeader title="Details" />
          <dl className="divide-y">
            {specs.map(([k, v]) => (
              <div key={k} className="flex justify-between gap-4 px-5 py-2.5 text-sm">
                <dt className="text-muted">{k}</dt>
                <dd className="truncate text-right font-medium">{v || <span className="font-normal text-muted">—</span>}</dd>
              </div>
            ))}
          </dl>
        </Card>

        {/* Timeline */}
        <Card className="lg:col-span-2">
          <CardHeader title="Status history" description={`${count ?? 0} report${count === 1 ? "" : "s"}`} />
          {rows.length === 0 ? (
            <EmptyState icon={History} title="No reports yet" description="Be the first to report this machine's status." />
          ) : (
            <ol className="px-5 py-5">
              {rows.map((r, i) => {
                const t = typeById.get(r.status_type_id);
                return (
                  <li key={r.id} className="relative flex gap-4 pb-6 last:pb-0">
                    {i < rows.length - 1 && <span className="absolute left-[7px] top-5 h-full w-px bg-border" aria-hidden />}
                    <span className="relative z-10 mt-1 size-[15px] shrink-0 rounded-full border-[3px] border-surface ring-1 ring-border" style={{ backgroundColor: t?.color ?? "var(--muted)" }} />
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                        <StatusBadge status={t} />
                        <span className="text-sm font-medium">{r.profiles?.name ?? "Unknown"}</span>
                        <span className="text-xs text-muted">{formatDateTime(r.reported_at, plant?.timezone)}</span>
                      </div>
                      {r.note && <p className="mt-2 whitespace-pre-wrap rounded-lg bg-surface-muted px-3 py-2 text-sm">{r.note}</p>}
                      {r.photo_path && photoUrl.get(r.photo_path) && <PhotoLightbox src={photoUrl.get(r.photo_path)!} alt={`Photo reported ${formatDateTime(r.reported_at, plant?.timezone)}`} />}
                    </div>
                  </li>
                );
              })}
            </ol>
          )}
          {pages > 1 && (
            <div className="flex items-center justify-between border-t px-5 py-3 text-sm">
              {page > 1 ? <Link href={`?page=${page - 1}`} className={buttonClass("secondary", "sm")}><ChevronLeft className="size-4" /> Newer</Link> : <span />}
              <span className="text-muted">Page {page} of {pages}</span>
              {page < pages ? <Link href={`?page=${page + 1}`} className={buttonClass("secondary", "sm")}>Older <ChevronRight className="size-4" /></Link> : <span />}
            </div>
          )}
        </Card>
      </div>
    </div>
  );
}
