import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { historyQuery, parseFilters } from "@/lib/history-query";

const csv = (v: unknown) => {
  let s = v == null ? "" : String(v);
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s; // neutralise spreadsheet formula injection
  return `"${s.replace(/"/g, '""')}"`;
};

export async function GET(request: NextRequest) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return new NextResponse("Unauthorized", { status: 401 });
  const { data: me } = await supabase.from("profiles").select("role,active").eq("id", user.id).maybeSingle();
  if (!me?.active || me.role === "worker") return new NextResponse("Forbidden", { status: 403 });

  const sp = Object.fromEntries(request.nextUrl.searchParams);
  const f = parseFilters(sp);
  const [{ data: types }, { data: plants }] = await Promise.all([
    supabase.from("status_types").select("id,label"),
    supabase.from("plants").select("id,name"),
  ]);
  const typeName = new Map((types ?? []).map((t) => [t.id, t.label]));
  const plantName = new Map((plants ?? []).map((p) => [p.id, p.name]));

  const lines = [["reported_at_utc", "plant", "equipment", "tag", "status", "reported_by", "note"].join(",")];
  const STEP = 1000;
  for (let from = 0; from < 200000; from += STEP) {
    const { data, error } = await historyQuery(
      supabase, f, "plant_id,status_type_id,note,reported_at,equipment(name,tag_code),profiles(name)",
    ).range(from, from + STEP - 1);
    if (error) return new NextResponse("Export failed", { status: 500 });
    type Row = {
      plant_id: string; status_type_id: string; note: string | null; reported_at: string;
      equipment: { name: string; tag_code: string } | null; profiles: { name: string } | null;
    };
    const rows = (data ?? []) as unknown as Row[];
    for (const r of rows) {
      lines.push([
        r.reported_at, plantName.get(r.plant_id), r.equipment?.name, r.equipment?.tag_code,
        typeName.get(r.status_type_id), r.profiles?.name, r.note,
      ].map(csv).join(","));
    }
    if (rows.length < STEP) break;
  }
  return new NextResponse("﻿" + lines.join("\r\n"), {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="status-history-${new Date().toISOString().slice(0, 10)}.csv"`,
    },
  });
}
