import Link from "next/link";
import { revalidatePath } from "next/cache";
import { getVisiblePlants, requireRole } from "@/lib/auth";

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

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-bold">Manage equipment</h1>
      {plants.length === 0 && <p className="text-gray-500">No plants yet. An admin must create a plant first.</p>}

      <form action={createEquipment} className="grid gap-2 sm:grid-cols-3">
        <select name="plant_id" required className="rounded border px-3 py-2">
          {plants.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select>
        <input name="tag_code" required placeholder="Tag code (unique)" className="rounded border px-3 py-2" />
        <input name="name" required placeholder="Name" className="rounded border px-3 py-2" />
        <input name="type" placeholder="Type (e.g. CNC lathe)" className="rounded border px-3 py-2" />
        <input name="manufacturer" placeholder="Manufacturer" className="rounded border px-3 py-2" />
        <input name="model" placeholder="Model" className="rounded border px-3 py-2" />
        <input name="serial_no" placeholder="Serial no." className="rounded border px-3 py-2" />
        <button className="rounded bg-blue-600 px-4 py-2 text-white sm:col-span-2">Add equipment</button>
      </form>

      <details>
        <summary className="cursor-pointer text-sm font-semibold">Bulk import (paste lines: tag,name,type)</summary>
        <form action={importEquipment} className="mt-2 flex flex-col gap-2">
          <select name="plant_id" required className="rounded border px-3 py-2">
            {plants.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
          <textarea name="csv" rows={5} placeholder={"CNC-01,CNC Lathe 1,Lathe\nPRS-07,Press 7,Press"} className="rounded border px-3 py-2 font-mono text-sm" />
          <button className="self-start rounded bg-blue-600 px-4 py-2 text-white">Import</button>
        </form>
      </details>

      <ul className="flex flex-col gap-2">
        {(items ?? []).map((e) => (
          <li key={e.id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg border p-3">
            <Link href={`/equipment/${e.id}`}>
              <strong>{e.name}</strong>{" "}
              <span className="text-sm text-gray-500">{e.tag_code} · {plantName.get(e.plant_id)}{!e.is_active && " · retired"}</span>
            </Link>
            <span className="flex gap-3 text-sm">
              <Link href={`/equipment/${e.id}/qr`} className="underline">QR</Link>
              <form action={setActive}>
                <input type="hidden" name="id" value={e.id} />
                <input type="hidden" name="active" value={String(!e.is_active)} />
                <button className="underline">{e.is_active ? "Retire" : "Restore"}</button>
              </form>
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}
