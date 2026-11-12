// Admin-only user operations that need the service-role key (which must never ship in the app):
//   { action: "invite", email, name, role, plant_ids, redirect_to }
//   { action: "set_active", id, active }
// The caller's JWT is verified and must belong to an active admin (public.is_admin()).
import { createClient } from "jsr:@supabase/supabase-js@2";

// ALLOWED_ORIGINS (function secret): comma-separated web origins of the app, e.g.
// "https://your-app.vercel.app". Browsers on other sites are refused, and invite links may only
// return to these origins or the mobile app. Unset = any origin (the old behaviour).
const allowedOrigins = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
  .split(",").map((o) => o.trim().replace(/\/$/, "")).filter(Boolean);
const MOBILE_REDIRECT = "com.equipmentportal.app://auth-callback";

const redirectAllowed = (to: string) =>
  allowedOrigins.length === 0 || to.startsWith(MOBILE_REDIRECT) ||
  allowedOrigins.some((o) => to === o || to.startsWith(o + "/"));

Deno.serve(async (req) => {
  const origin = req.headers.get("Origin") ?? "";
  const cors = {
    "Access-Control-Allow-Origin": allowedOrigins.length === 0 ? "*" : (allowedOrigins.includes(origin) ? origin : allowedOrigins[0]),
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization") ?? "";

  // Client acting as the caller: RLS applies to everything it does.
  const asCaller = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const { data: { user } } = await asCaller.auth.getUser();
  if (!user) return json({ error: "Not signed in" }, 401);
  const { data: isAdmin } = await asCaller.rpc("is_admin");
  if (!isAdmin) return json({ error: "Admins only" }, 403);

  const admin = createClient(url, service, { auth: { persistSession: false } });
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  if (body.action === "invite") {
    const email = String(body.email ?? "").trim().toLowerCase();
    const name = String(body.name ?? "").trim();
    const role = String(body.role ?? "worker");
    const plantIds = Array.isArray(body.plant_ids) ? body.plant_ids.map(String) : [];
    const redirectTo = typeof body.redirect_to === "string" ? body.redirect_to : undefined;
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || !name || !["worker", "manager", "admin"].includes(role)) {
      return json({ error: "Name, a valid email and a role are required" }, 400);
    }
    if (redirectTo !== undefined && !redirectAllowed(redirectTo)) {
      return json({ error: "Invite links can only return to this app" }, 400);
    }
    // The invite row must exist first: the DB trigger only creates profiles for invited emails.
    await asCaller.from("invites").delete().eq("email", email).is("used_at", null);
    const { error: invErr } = await asCaller.from("invites").insert({ email, name, role, plant_ids: plantIds, invited_by: user.id });
    if (invErr) return json({ error: invErr.message }, 400);

    const { error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo });
    if (error) {
      // Don't leave an unused invite lying around for 7 days.
      await asCaller.from("invites").delete().eq("email", email).is("used_at", null);
      const exists = /already been registered|already exists/i.test(error.message);
      return json({ error: exists ? "This email already has an account." : error.message }, 400);
    }
    return json({ ok: true });
  }

  if (body.action === "set_active") {
    const id = String(body.id ?? "");
    const active = body.active === true;
    if (!id) return json({ error: "Missing user id" }, 400);
    if (id === user.id) return json({ error: "You cannot deactivate yourself" }, 400);
    const { error: upErr } = await asCaller.from("profiles").update({ active }).eq("id", id);
    if (upErr) return json({ error: upErr.message }, 400);
    // Block token refresh too, so a deactivated person's phone can never get a new session.
    const { error } = await admin.auth.admin.updateUserById(id, { ban_duration: active ? "none" : "876000h" });
    if (error) return json({ error: error.message }, 400);
    return json({ ok: true });
  }

  return json({ error: "Unknown action" }, 400);
});
