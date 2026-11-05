import { notFound } from "next/navigation";
import Link from "next/link";
import { requireUser } from "@/lib/auth";
import type { StatusType } from "@/lib/types";
import StatusForm from "./status-form";

export default async function UpdatePage(props: PageProps<"/equipment/[id]/update">) {
  const { id } = await props.params;
  const { supabase, profile } = await requireUser();

  const { data: eq } = await supabase
    .from("equipment")
    .select("id,name,tag_code,is_active,plants(name)")
    .eq("id", id)
    .maybeSingle();

  if (!eq) {
    return (
      <div className="mx-auto max-w-md p-4">
        <h1 className="text-lg font-bold">Equipment not available</h1>
        <p className="text-sm text-gray-600">
          This machine doesn&apos;t exist or isn&apos;t in a plant you&apos;re assigned to. Ask your manager if you need access.
        </p>
        <Link href="/equipment" className="text-blue-600 underline">Back to equipment</Link>
      </div>
    );
  }
  if (!eq.is_active) notFound();

  const { data: types } = await supabase
    .from("status_types")
    .select("id,key,label,color,is_failure,sort_order")
    .eq("active", true)
    .order("sort_order");

  const plant = eq.plants as unknown as { name: string } | null;

  return (
    <StatusForm
      userId={profile.id}
      equipment={{ id: eq.id, name: eq.name, tag: eq.tag_code, plant: plant?.name ?? "" }}
      statusTypes={(types ?? []) as StatusType[]}
    />
  );
}
