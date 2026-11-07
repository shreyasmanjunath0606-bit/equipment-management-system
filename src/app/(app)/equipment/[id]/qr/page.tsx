import Link from "next/link";
import { notFound } from "next/navigation";
import QRCode from "qrcode";
import { ArrowLeft, Factory, ScanLine } from "lucide-react";
import { requireRole } from "@/lib/auth";
import PrintButton from "@/components/print-button";
import { buttonClass } from "@/components/ui";

export default async function QrPage(props: PageProps<"/equipment/[id]/qr">) {
  const { id } = await props.params;
  const { supabase } = await requireRole("manager", "admin");
  const { data: eq } = await supabase.from("equipment").select("id,name,tag_code").eq("id", id).maybeSingle();
  if (!eq) notFound();

  const base = (process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000").replace(/\/$/, "");
  const url = `${base}/equipment/${eq.id}/update`;
  const svg = await QRCode.toString(url, { type: "svg", margin: 0, width: 240 });

  return (
    <div className="mx-auto flex max-w-md flex-col items-center gap-6">
      <div className="flex w-full items-center justify-between print:hidden">
        <Link href={`/equipment/${eq.id}`} className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" /> Back</Link>
        <PrintButton />
      </div>

      {/* Label — white regardless of theme so it prints cleanly */}
      <div className="w-full max-w-xs overflow-hidden rounded-2xl border-2 border-slate-900 bg-white text-slate-900 shadow-lg print:shadow-none">
        <div className="flex items-center gap-2 bg-slate-900 px-4 py-2.5 text-white">
          <Factory className="size-4" />
          <span className="text-xs font-semibold uppercase tracking-wider">Equipment Portal</span>
        </div>
        <div className="flex flex-col items-center gap-4 p-6 text-center">
          <div className="[&_svg]:h-auto [&_svg]:w-full" dangerouslySetInnerHTML={{ __html: svg }} />
          <div>
            <p className="text-lg font-bold leading-tight">{eq.name}</p>
            <p className="mt-1 font-mono text-sm font-semibold tracking-wider">{eq.tag_code}</p>
          </div>
          <p className="flex items-center gap-1.5 text-xs text-slate-600"><ScanLine className="size-3.5" /> Scan to report status</p>
        </div>
      </div>

      <p className="max-w-xs break-all text-center text-[11px] text-muted print:hidden">{url}</p>
      <p className="text-center text-sm text-muted print:hidden">Print this and stick it on the machine. Scanning opens the report form.</p>
    </div>
  );
}
