import { revalidatePath } from "next/cache";
import { requireRole } from "@/lib/auth";

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
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-bold">Plants</h1>
      <form action={createPlant} className="flex flex-wrap gap-2">
        <input name="name" required placeholder="Plant name" className="rounded border px-3 py-2" />
        <input name="code" required placeholder="Code (e.g. PUNE)" className="w-32 rounded border px-3 py-2" />
        <input name="timezone" defaultValue="Asia/Kolkata" placeholder="Timezone" className="rounded border px-3 py-2" />
        <button className="rounded bg-blue-600 px-4 py-2 text-white">Add plant</button>
      </form>
      <ul className="flex flex-col gap-2">
        {(plants ?? []).map((p) => (
          <li key={p.id} className="flex items-center justify-between rounded-lg border p-3">
            <span>
              <strong>{p.name}</strong> <span className="text-sm text-gray-500">{p.code} · {p.timezone}{!p.active && " · inactive"}</span>
            </span>
            <form action={setPlantActive}>
              <input type="hidden" name="id" value={p.id} />
              <input type="hidden" name="active" value={String(!p.active)} />
              <button className="text-sm underline">{p.active ? "Deactivate" : "Reactivate"}</button>
            </form>
          </li>
        ))}
      </ul>
    </div>
  );
}
