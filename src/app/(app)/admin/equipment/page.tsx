import Link from "next/link";
import { revalidatePath } from "next/cache";
import { Archive, ArchiveRestore, Building2, Plus, QrCode, Upload, Wrench } from "lucide-react";
import { getVisiblePlants, requireRole } from "@/lib/auth";
import { Card, EmptyState, Input, Label, PageHeader, Pill, Select, Table, Textarea, buttonClass, tdClass, thClass } from "@/components/ui";
import { ConfirmButton, Modal, SubmitButton } from "@/components/form-controls";

async function createEquipment(formData: FormData) {
  "use server";
  const { supabase } = await requireRole("manager", "admin");
  const str = (k: string) => String(formData.get(k) ?? "").trim();
  if (!str("tag_code") || !str("name") || !str("plant_id")) return;
  await supabase.from("equipment").insert({
    tag_code: str("tag_code"), name: str("name"), type: str("type") || null, plant_id: str("plant_id"),
    manufacturer: str("manufacturer") || null, model: str("model") || null, serial_no: str("serial_no") || null,
  });
  revalidatePath("/admin/equipment");
}

// Bulk add: one machine per line  ->  tag,name,type
async function importEquipment(formData: FormData) {
  "use server";
  const { supabase } = await requireRole("manager", "admin");
  const plant_id = String(formData.get("plant_id") ?? "");
  const rows = String(formData.get("csv") ?? "")
    .split(/\r?\n/)
    .map((l) => l.split(",").map((c) => c.trim()))
    .filter((c) => c[0] && c[1])
    .slice(0, 500)
    .map(([tag_code, name, type]) => ({ tag_code, name, type: type || null, plant_id }));
  if (plant_id && rows.length) await supabase.from("equipment").insert(rows);
  revalidatePath("/admin/equipment");
}

// Machines are retired, never deleted, so their history stays readable.
async function setActive(formData: FormData) {
  "use server";
  const { supabase } = await requireRole("manager", "admin");
  await supabase.from("equipment").update({ is_active: formData.get("active") === "true" }).eq("id", String(formData.get("id")));
  revalidatePath("/admin/equipment");
}

export default async function EquipmentAdmin() {
  const { supabase } = await requireRole("manager", "admin");
  const plants = await getVisiblePlants();
  const { data: items } = await supabase
    .from("equipment")
    .select("id,tag_code,name,type,plant_id,is_active")
    .order("created_at", { ascending: false })
    .limit(100);
  const plantName = new Map(plants.map((p) => [p.id, p.name]));

  const list = items ?? [];
  const plantSelect = (
    <Select name="plant_id" required>
      {plants.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
    </Select>
  );

  return (
    <div>
      <PageHeader
        title="Manage equipment"
        description={`${list.filter((e) => e.is_active).length} active · ${list.filter((e) => !e.is_active).length} retired (latest 100)`}
        actions={plants.length > 0 && (
          <>
            <Modal triggerVariant="secondary" trigger={<><Upload className="size-4" /> Bulk import</>} title="Bulk import" description="Paste one machine per line: tag,name,type (max 500).">
              <form action={importEquipment} className="flex flex-col gap-4">
                <div><Label>Plant</Label>{plantSelect}</div>
                <div>
                  <Label>Equipment lines</Label>
                  <Textarea name="csv" rows={7} placeholder={"CNC-01,CNC Lathe 1,Lathe\nPRS-07,Press 7,Press"} className="font-mono text-xs" />
                </div>
                <div className="flex justify-end"><SubmitButton pendingText="Importing…">Import</SubmitButton></div>
              </form>
            </Modal>
            <Modal trigger={<><Plus className="size-4" /> Add equipment</>} title="Add equipment" description="Tag codes must be unique within the system.">
              <form action={createEquipment} className="grid gap-4 sm:grid-cols-2">
                <div className="sm:col-span-2"><Label>Plant *</Label>{plantSelect}</div>
                <div><Label htmlFor="tag_code">Tag code *</Label><Input id="tag_code" name="tag_code" required placeholder="CNC-01" className="font-mono" /></div>
                <div><Label htmlFor="name">Name *</Label><Input id="name" name="name" required placeholder="CNC Lathe 1" /></div>
                <div><Label htmlFor="type">Type</Label><Input id="type" name="type" placeholder="Lathe" /></div>
                <div><Label htmlFor="manufacturer">Manufacturer</Label><Input id="manufacturer" name="manufacturer" /></div>
                <div><Label htmlFor="model">Model</Label><Input id="model" name="model" /></div>
                <div><Label htmlFor="serial_no">Serial no.</Label><Input id="serial_no" name="serial_no" /></div>
                <div className="flex justify-end sm:col-span-2"><SubmitButton pendingText="Adding…">Add equipment</SubmitButton></div>
              </form>
            </Modal>
          </>
        )}
      />

      <Card className="overflow-hidden">
        {plants.length === 0 ? (
          <EmptyState icon={Building2} title="No plants yet" description="An admin must create a plant before equipment can be added." />
        ) : list.length === 0 ? (
          <EmptyState icon={Wrench} title="No equipment yet" description="Add your first machine or bulk-import a list." />
        ) : (
          <Table>
            <thead>
              <tr>
                <th className={thClass}>Equipment</th>
                <th className={thClass}>Tag</th>
                <th className={`${thClass} hidden sm:table-cell`}>Plant</th>
                <th className={thClass}>State</th>
                <th className={`${thClass} text-right`}><span className="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody>
              {list.map((e) => (
                <tr key={e.id} className={e.is_active ? "hover:bg-surface-muted/60" : "bg-surface-muted/30 text-muted"}>
                  <td className={tdClass}>
                    <Link href={`/equipment/${e.id}`} className="font-medium hover:text-primary">{e.name}</Link>
                    {e.type && <div className="text-xs text-muted">{e.type}</div>}
                  </td>
                  <td className={`${tdClass} font-mono text-xs`}>{e.tag_code}</td>
                  <td className={`${tdClass} hidden sm:table-cell`}>{plantName.get(e.plant_id)}</td>
                  <td className={tdClass}>
                    {e.is_active
                      ? <Pill className="border-success/30 bg-success/10 text-success">Active</Pill>
                      : <Pill>Retired</Pill>}
                  </td>
                  <td className={tdClass}>
                    <div className="flex justify-end gap-2">
                      <Link href={`/equipment/${e.id}/qr`} className={buttonClass("ghost", "sm")} aria-label={`QR code for ${e.name}`}><QrCode className="size-4" /></Link>
                      <form action={setActive}>
                        <input type="hidden" name="id" value={e.id} />
                        <input type="hidden" name="active" value={String(!e.is_active)} />
                        {e.is_active ? (
                          <ConfirmButton title={`Retire ${e.name}?`} description="It will be hidden from the equipment list. Its history stays readable and you can restore it later." confirmLabel="Retire">
                            <Archive className="size-3.5" /> Retire
                          </ConfirmButton>
                        ) : (
                          <SubmitButton variant="secondary" size="sm"><ArchiveRestore className="size-3.5" /> Restore</SubmitButton>
                        )}
                      </form>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    </div>
  );
}
