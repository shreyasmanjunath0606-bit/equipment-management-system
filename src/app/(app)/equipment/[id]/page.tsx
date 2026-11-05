import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth";
import { StatusBadge, formatDateTime, timeAgo } from "@/components/status-badge";
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

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold">{eq.name}</h1>
          <p className="text-sm text-gray-500">
            {eq.tag_code} · {plant?.name}{area ? ` · ${area.name}` : ""}{eq.type ? ` · ${eq.type}` : ""}
            {!eq.is_active && " · RETIRED"}
          </p>
          <div className="mt-2 flex items-center gap-2">
            <StatusBadge status={current} />
            {rows[0] && page === 1 && <span className="text-xs text-gray-500">{timeAgo(rows[0].reported_at)}</span>}
          </div>
        </div>
        <div className="flex gap-2">
          {profile.role !== "worker" && <Link href={`/equipment/${id}/qr`} className="rounded-lg border px-3 py-2 text-sm">QR code</Link>}
          {eq.is_active && (
            <Link href={`/equipment/${id}/update`} className="rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white">
              Report status
            </Link>
          )}
        </div>
      </div>

      <h2 className="font-semibold">History ({count ?? 0})</h2>
      <ol className="flex flex-col gap-2">
        {rows.length === 0 && <li className="text-gray-500">No reports yet.</li>}
        {rows.map((r) => (
          <li key={r.id} className="rounded-lg border p-3">
            <div className="flex flex-wrap items-center gap-2">
              <StatusBadge status={typeById.get(r.status_type_id)} />
              <span className="text-sm">{formatDateTime(r.reported_at, plant?.timezone)}</span>
              <span className="text-xs text-gray-500">by {r.profiles?.name ?? "unknown"}</span>
            </div>
            {r.note && <p className="mt-1 whitespace-pre-wrap text-sm">{r.note}</p>}
            {r.photo_path && photoUrl.get(r.photo_path) && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={photoUrl.get(r.photo_path)} alt="Failure photo" className="mt-2 max-h-60 rounded" loading="lazy" />
            )}
          </li>
        ))}
      </ol>
      <div className="flex items-center justify-between text-sm">
        {page > 1 ? <Link href={`?page=${page - 1}`}>← Newer</Link> : <span />}
        <span className="text-gray-500">Page {page} of {pages}</span>
        {page < pages ? <Link href={`?page=${page + 1}`}>Older →</Link> : <span />}
      </div>
    </div>
  );
}
