import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

async function handle(request: NextRequest) {
  const supabase = await createClient();
  await supabase.auth.signOut();
  const url = request.nextUrl.clone();
  const reason = url.searchParams.get("reason");
  url.pathname = "/login";
  url.search = reason === "deactivated" ? "?error=deactivated" : "";
  return NextResponse.redirect(url, { status: 303 });
}

export const GET = handle;
export const POST = handle;
