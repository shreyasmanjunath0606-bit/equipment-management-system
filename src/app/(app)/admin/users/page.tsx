import { revalidatePath } from "next/cache";
import { Mail, Send, UserCheck, UserPlus, UserX } from "lucide-react";
import { requireRole } from "@/lib/auth";
import { Card, CardHeader, Input, Label, PageHeader, Pill, Select } from "@/components/ui";
import { ConfirmButton, Modal, SubmitButton } from "@/components/form-controls";
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

  const ROLE_STYLE: Record<string, string> = {
    admin: "border-violet-300/50 bg-violet-500/10 text-violet-700 dark:text-violet-300",
    manager: "border-primary/30 bg-primary-soft text-primary",
    worker: "",
  };
  const checkbox = "size-4 rounded border accent-[var(--primary)]";
  const list = users ?? [];
  const invites = pending ?? [];

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Users"
        description={`${list.filter((u) => u.active).length} active · ${invites.length} pending invite${invites.length === 1 ? "" : "s"}`}
        actions={
          <Modal trigger={<><UserPlus className="size-4" /> Invite person</>} title="Invite a person" description="They'll get an email link to set a password.">
            <form action={inviteUser} className="flex flex-col gap-4">
              <div className="grid gap-4 sm:grid-cols-2">
                <div><Label htmlFor="name">Full name</Label><Input id="name" name="name" required /></div>
                <div><Label htmlFor="email">Email</Label><Input id="email" name="email" type="email" required /></div>
              </div>
              <div>
                <Label htmlFor="role">Role</Label>
                <Select id="role" name="role">
                  <option value="worker">Worker — reports status</option>
                  <option value="manager">Manager — dashboard, alerts, equipment</option>
                  <option value="admin">Admin — all plants, users</option>
                </Select>
              </div>
              <fieldset>
                <legend className="mb-1.5 text-xs font-medium text-muted">Plants</legend>
                <div className="grid grid-cols-2 gap-2">
                  {(plants ?? []).map((p) => (
                    <label key={p.id} className="flex items-center gap-2 rounded-lg border px-3 py-2 text-sm hover:bg-surface-muted">
                      <input type="checkbox" name="plant_ids" value={p.id} className={checkbox} /> {p.name}
                    </label>
                  ))}
                </div>
              </fieldset>
              <div className="flex justify-end"><SubmitButton pendingText="Sending…"><Send className="size-4" /> Send invite</SubmitButton></div>
            </form>
          </Modal>
        }
      />

      {invites.length > 0 && (
        <Card>
          <CardHeader title="Pending invites" />
          <ul className="flex flex-wrap gap-2 p-4">
            {invites.map((p) => (
              <li key={p.id}><Pill><Mail className="size-3" /> {p.email} <span className="capitalize text-muted">· {p.role}</span></Pill></li>
            ))}
          </ul>
        </Card>
      )}

      <Card className="overflow-hidden">
        <ul className="divide-y">
          {list.map((u) => (
            <li key={u.id} className={`flex flex-col gap-3 p-4 sm:flex-row sm:items-center ${u.active ? "" : "bg-surface-muted/40"}`}>
              <div className="flex min-w-0 flex-1 items-center gap-3">
                <span className={`flex size-9 shrink-0 items-center justify-center rounded-full text-xs font-semibold ${u.active ? "bg-primary-soft text-primary" : "bg-surface-muted text-muted"}`}>
                  {(u.name || u.email).split(/\s+/).map((s: string) => s[0]).slice(0, 2).join("").toUpperCase()}
                </span>
                <div className="min-w-0">
                  <p className="flex flex-wrap items-center gap-2 font-medium">
                    {u.name}
                    <Pill className={`capitalize ${ROLE_STYLE[u.role] ?? ""}`}>{u.role}</Pill>
                    {!u.active && <Pill className="border-danger/30 bg-danger-soft text-danger">Deactivated</Pill>}
                    {u.id === user.id && <span className="text-xs text-muted">(you)</span>}
                  </p>
                  <p className="truncate text-xs text-muted">{u.email}</p>
                </div>
              </div>

              {u.role !== "admin" ? (
                <form action={setUserPlants} className="flex flex-wrap items-center gap-2">
                  <input type="hidden" name="id" value={u.id} />
                  {(plants ?? []).map((p) => (
                    <label key={p.id} className="flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs hover:bg-surface-muted has-[:checked]:border-primary/40 has-[:checked]:bg-primary-soft has-[:checked]:text-primary">
                      <input type="checkbox" name="plant_ids" value={p.id} defaultChecked={byUser.get(u.id)?.has(p.id)} className="size-3.5 accent-[var(--primary)]" /> {p.name}
                    </label>
                  ))}
                  <SubmitButton variant="ghost" size="sm" pendingText="Saving…">Save</SubmitButton>
                </form>
              ) : (
                <span className="text-xs text-muted">All plants</span>
              )}

              {u.id !== user.id && (
                <form action={setUserActive}>
                  <input type="hidden" name="id" value={u.id} />
                  <input type="hidden" name="active" value={String(!u.active)} />
                  {u.active ? (
                    <ConfirmButton title={`Deactivate ${u.name}?`} description="They will be signed out everywhere and can't sign in until reactivated." confirmLabel="Deactivate">
                      <UserX className="size-3.5" /> Deactivate
                    </ConfirmButton>
                  ) : (
                    <SubmitButton variant="secondary" size="sm"><UserCheck className="size-3.5" /> Reactivate</SubmitButton>
                  )}
                </form>
              )}
            </li>
          ))}
        </ul>
      </Card>
    </div>
  );
}
