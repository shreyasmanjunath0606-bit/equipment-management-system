import { revalidatePath } from "next/cache";
import { Building2, Clock, Plus } from "lucide-react";
import { requireRole } from "@/lib/auth";
import { Card, EmptyState, Input, Label, PageHeader, Pill } from "@/components/ui";
import { ConfirmButton, Modal, SubmitButton } from "@/components/form-controls";

async function createPlant(formData: FormData) {
  "use server";
  const { supabase } = await requireRole("admin");
  const name = String(formData.get("name") ?? "").trim();
  const code = String(formData.get("code") ?? "").trim().toUpperCase();
  const timezone = String(formData.get("timezone") ?? "UTC").trim() || "UTC";
  if (!name || !code) return;
  try {
    new Intl.DateTimeFormat(undefined, { timeZone: timezone });
  } catch {
    return;
  }
  await supabase.from("plants").insert({ name, code, timezone });
  revalidatePath("/admin/plants");
}

async function setPlantActive(formData: FormData) {
  "use server";
  const { supabase } = await requireRole("admin");
  await supabase.from("plants").update({ active: formData.get("active") === "true" }).eq("id", String(formData.get("id")));
  revalidatePath("/admin/plants");
}

export default async function PlantsAdmin() {
  const { supabase } = await requireRole("admin");
  const { data: plants } = await supabase.from("plants").select("id,code,name,timezone,active").order("name");

  return (
    <div>
      <PageHeader
        title="Plants"
        description="Sites that equipment and users belong to."
        actions={
          <Modal trigger={<><Plus className="size-4" /> Add plant</>} title="Add plant">
            <form action={createPlant} className="grid gap-4 sm:grid-cols-2">
              <div className="sm:col-span-2"><Label htmlFor="name">Plant name</Label><Input id="name" name="name" required placeholder="Pune Assembly" /></div>
              <div><Label htmlFor="code">Code</Label><Input id="code" name="code" required placeholder="PUNE" className="font-mono uppercase" /></div>
              <div><Label htmlFor="timezone">Timezone</Label><Input id="timezone" name="timezone" defaultValue="Asia/Kolkata" placeholder="Asia/Kolkata" /></div>
              <div className="flex justify-end sm:col-span-2"><SubmitButton pendingText="Adding…">Add plant</SubmitButton></div>
            </form>
          </Modal>
        }
      />
      {(plants ?? []).length === 0 ? (
        <Card><EmptyState icon={Building2} title="No plants yet" description="Add your first plant to start registering equipment." /></Card>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {(plants ?? []).map((p) => (
            <Card key={p.id} className={`flex flex-col gap-4 p-5 ${p.active ? "" : "opacity-70"}`}>
              <div className="flex items-start justify-between gap-3">
                <div className="flex items-center gap-3">
                  <span className="flex size-10 items-center justify-center rounded-lg bg-primary-soft text-primary"><Building2 className="size-5" /></span>
                  <div>
                    <p className="font-semibold">{p.name}</p>
                    <p className="font-mono text-xs text-muted">{p.code}</p>
                  </div>
                </div>
                {p.active ? <Pill className="border-success/30 bg-success/10 text-success">Active</Pill> : <Pill>Inactive</Pill>}
              </div>
              <p className="flex items-center gap-1.5 text-xs text-muted"><Clock className="size-3.5" /> {p.timezone}</p>
              <form action={setPlantActive} className="mt-auto border-t pt-3">
                <input type="hidden" name="id" value={p.id} />
                <input type="hidden" name="active" value={String(!p.active)} />
                {p.active ? (
                  <ConfirmButton title={`Deactivate ${p.name}?`} description="The plant will be hidden from plant pickers. Its equipment and history are kept." confirmLabel="Deactivate">Deactivate</ConfirmButton>
                ) : (
                  <SubmitButton variant="secondary" size="sm">Reactivate</SubmitButton>
                )}
              </form>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
