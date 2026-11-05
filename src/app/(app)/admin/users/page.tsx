import { revalidatePath } from "next/cache";
import { requireRole } from "@/lib/auth";
import { createAdminClient } from "@/lib/supabase/admin";

async function inviteUser(formData: FormData) {
  "use server";
  const { supabase, user } = await requireRole("admin");
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const name = String(formData.get("name") ?? "").trim();
  const role = String(formData.get("role") ?? "worker");
  const plant_ids = formData.getAll("plant_ids").map(String);
  if (!email || !name || !["worker", "manager", "admin"].includes(role)) return;

  // Invite row first: the DB trigger only creates a profile for emails that have one.
  await supabase.from("invites").delete().ilike("email", email).is("used_at", null);
  const { error } = await supabase.from("invites").insert({ email, name, role, plant_ids, invited_by: user.id });
  if (error) return;

  const site = (process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000").replace(/\/$/, "");
  await createAdminClient().auth.admin.inviteUserByEmail(email, { redirectTo: `${site}/auth/confirm?next=/set-password` });
  revalidatePath("/admin/users");
}

async function setUserActive(formData: FormData) {
  "use server";
  const { supabase, user } = await requireRole("admin");
  const id = String(formData.get("id"));
  const active = formData.get("active") === "true";
  if (id === user.id) return; // don't lock yourself out
  await supabase.from("profiles").update({ active }).eq("id", id);
  // Block token refresh too, so a deactivated person's phone can never get a new session.
  await createAdminClient().auth.admin.updateUserById(id, { ban_duration: active ? "none" : "876000h" });
  revalidatePath("/admin/users");
}

async function setUserPlants(formData: FormData) {
  "use server";
  const { supabase } = await requireRole("admin");
  const id = String(formData.get("id"));
  const plant_ids = formData.getAll("plant_ids").map(String);
  await supabase.from("user_plants").delete().eq("user_id", id);
  if (plant_ids.length) await supabase.from("user_plants").insert(plant_ids.map((plant_id) => ({ user_id: id, plant_id })));
  revalidatePath("/admin/users");
}

export default async function UsersAdmin() {
  const { supabase, user } = await requireRole("admin");
  const [{ data: users }, { data: plants }, { data: ups }, { data: pending }] = await Promise.all([
    supabase.from("profiles").select("id,name,email,role,active").order("name"),
    supabase.from("plants").select("id,name").eq("active", true).order("name"),
    supabase.from("user_plants").select("user_id,plant_id"),
    supabase.from("invites").select("id,email,name,role,expires_at").is("used_at", null),
  ]);
  const byUser = new Map<string, Set<string>>();
  (ups ?? []).forEach((u) => byUser.set(u.user_id, (byUser.get(u.user_id) ?? new Set()).add(u.plant_id)));

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-bold">Users</h1>

      <form action={inviteUser} className="flex flex-col gap-2 rounded-lg border p-3">
        <strong>Invite a person</strong>
        <div className="flex flex-wrap gap-2">
          <input name="name" required placeholder="Full name" className="rounded border px-3 py-2" />
          <input name="email" type="email" required placeholder="Email" className="rounded border px-3 py-2" />
          <select name="role" className="rounded border px-3 py-2">
            <option value="worker">Worker</option>
            <option value="manager">Manager</option>
            <option value="admin">Admin (all plants)</option>
          </select>
        </div>
        <div className="flex flex-wrap gap-3 text-sm">
          {(plants ?? []).map((p) => (
            <label key={p.id} className="flex items-center gap-1"><input type="checkbox" name="plant_ids" value={p.id} /> {p.name}</label>
          ))}
        </div>
        <button className="self-start rounded bg-blue-600 px-4 py-2 text-white">Send invite</button>
      </form>

      {(pending ?? []).length > 0 && (
        <p className="text-sm text-gray-500">
          Pending invites: {(pending ?? []).map((p) => p.email).join(", ")}
        </p>
      )}

      <ul className="flex flex-col gap-2">
        {(users ?? []).map((u) => (
          <li key={u.id} className={`rounded-lg border p-3 ${u.active ? "" : "opacity-60"}`}>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span><strong>{u.name}</strong> <span className="text-sm text-gray-500">{u.email} · {u.role}{!u.active && " · deactivated"}</span></span>
              {u.id !== user.id && (
                <form action={setUserActive}>
                  <input type="hidden" name="id" value={u.id} />
                  <input type="hidden" name="active" value={String(!u.active)} />
                  <button className="text-sm underline">{u.active ? "Deactivate" : "Reactivate"}</button>
                </form>
              )}
            </div>
            {u.role !== "admin" && (
              <form action={setUserPlants} className="mt-2 flex flex-wrap items-center gap-3 text-sm">
                <input type="hidden" name="id" value={u.id} />
                {(plants ?? []).map((p) => (
                  <label key={p.id} className="flex items-center gap-1">
                    <input type="checkbox" name="plant_ids" value={p.id} defaultChecked={byUser.get(u.id)?.has(p.id)} /> {p.name}
                  </label>
                ))}
                <button className="underline">Save plants</button>
              </form>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}
