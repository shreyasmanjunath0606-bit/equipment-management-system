import { notFound } from "next/navigation";
import QRCode from "qrcode";
import { requireRole } from "@/lib/auth";

export default async function QrPage(props: PageProps<"/equipment/[id]/qr">) {
  const { id } = await props.params;
  const { supabase } = await requireRole("manager", "admin");
  const { data: eq } = await supabase.from("equipment").select("id,name,tag_code").eq("id", id).maybeSingle();
  if (!eq) notFound();

  const base = (process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000").replace(/\/$/, "");
  const url = `${base}/equipment/${eq.id}/update`;
  const svg = await QRCode.toString(url, { type: "svg", margin: 1, width: 280 });

  return (
    <div className="mx-auto flex max-w-sm flex-col items-center gap-3 text-center print:max-w-none">
      <h1 className="text-xl font-bold">{eq.name}</h1>
      <p className="text-sm text-gray-500">{eq.tag_code}</p>
      <div className="bg-white p-2" dangerouslySetInnerHTML={{ __html: svg }} />
      <p className="text-xs break-all text-gray-500">{url}</p>
      <p className="text-sm print:hidden">Print this and stick it on the machine. Scanning opens the report form.</p>
    </div>
  );
}
