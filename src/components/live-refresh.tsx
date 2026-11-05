"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

/** Re-fetches the server-rendered page whenever a new status event arrives (RLS limits what we hear about). */
export default function LiveRefresh() {
  const router = useRouter();
  useEffect(() => {
    const supabase = createClient();
    let t: ReturnType<typeof setTimeout> | undefined;
    const channel = supabase
      .channel("status-events-live")
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "status_events" }, () => {
        clearTimeout(t);
        t = setTimeout(() => router.refresh(), 500);
      })
      .subscribe();
    return () => {
      clearTimeout(t);
      supabase.removeChannel(channel);
    };
  }, [router]);
  return null;
}
