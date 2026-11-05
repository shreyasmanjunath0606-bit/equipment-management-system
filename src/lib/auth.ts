import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { Plant, Profile, Role } from "@/lib/types";

/** Only allow same-site relative redirects. */
export function safeNext(next: string | null | undefined, fallback = "/"): string {
  if (!next || !next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) return fallback;
  return next;
}

export const getSession = cache(async () => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("id,name,email,role,active")
    .eq("id", user.id)
    .maybeSingle<Profile>();

  return { supabase, user, profile };
});

/** Require a signed-in, active user; deactivated users are signed out. */
export async function requireUser() {
  const s = await getSession();
  if (!s) redirect("/login");
  if (!s.profile || !s.profile.active) redirect("/auth/signout?reason=deactivated");
  return { supabase: s.supabase, user: s.user, profile: s.profile };
}

export async function requireRole(...roles: Role[]) {
  const ctx = await requireUser();
  if (!roles.includes(ctx.profile.role)) redirect("/");
  return ctx;
}

export const getVisiblePlants = cache(async (): Promise<Plant[]> => {
  const supabase = await createClient();
  const { data } = await supabase
    .from("plants")
    .select("id,code,name,timezone")
    .eq("active", true)
    .order("name");
  return (data ?? []) as Plant[];
});
