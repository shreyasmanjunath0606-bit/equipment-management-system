import { notFound } from "next/navigation";
import Link from "next/link";
import { ShieldAlert } from "lucide-react";
import { requireUser } from "@/lib/auth";
import { Card, EmptyState, buttonClass } from "@/components/ui";
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
      <Card className="mx-auto max-w-md">
        <EmptyState
          icon={ShieldAlert}
          title="Equipment not available"
          description="This machine doesn't exist or isn't in a plant you're assigned to. Ask your manager if you need access."
          action={<Link href="/equipment" className={buttonClass("secondary")}>Back to equipment</Link>}
        />
      </Card>
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
