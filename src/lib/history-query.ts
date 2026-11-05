import type { SupabaseClient } from "@supabase/supabase-js";

export interface HistoryFilters {
  plant: string;
  status: string;
  from: string;
  to: string;
  q: string;
}

export function parseFilters(sp: Record<string, string | string[] | undefined>): HistoryFilters {
  const s = (k: string) => (typeof sp[k] === "string" ? (sp[k] as string).trim() : "");
  const date = (v: string) => (/^\d{4}-\d{2}-\d{2}$/.test(v) ? v : "");
  return { plant: s("plant"), status: s("status"), from: date(s("from")), to: date(s("to")), q: s("q") };
}

/** Builds the history query (RLS already limits rows to plants the user can access). */
export function historyQuery(supabase: SupabaseClient, f: HistoryFilters, columns: string, withCount = false) {
  let query = supabase
    .from("status_events")
    .select(columns, withCount ? { count: "exact" } : undefined)
    .order("reported_at", { ascending: false })
    .order("id", { ascending: false });
  if (f.plant) query = query.eq("plant_id", f.plant);
  if (f.status) query = query.eq("status_type_id", f.status);
  if (f.from) query = query.gte("reported_at", `${f.from}T00:00:00Z`);
  if (f.to) query = query.lt("reported_at", new Date(new Date(`${f.to}T00:00:00Z`).getTime() + 86400000).toISOString());
  return query;
}
