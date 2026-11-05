"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import type { NotificationRow } from "@/lib/types";

export default function NotificationBell({ userId }: { userId: string }) {
  const [items, setItems] = useState<NotificationRow[]>([]);
  const [open, setOpen] = useState(false);

  const load = useCallback(async () => {
    const { data } = await createClient()
      .from("notifications")
      .select("id,equipment_id,kind,message,read_at,created_at")
      .order("created_at", { ascending: false })
      .limit(30);
    setItems((data ?? []) as NotificationRow[]);
  }, []);

  useEffect(() => {
    const supabase = createClient();
    const timer = setTimeout(load, 0);
    const channel = supabase
      .channel(`notifications:${userId}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "notifications", filter: `user_id=eq.${userId}` },
        () => load(),
      )
      .subscribe();
    return () => {
      clearTimeout(timer);
      supabase.removeChannel(channel);
    };
  }, [userId, load]);

  const unread = items.filter((i) => !i.read_at).length;

  async function markAllRead() {
    const ids = items.filter((i) => !i.read_at).map((i) => i.id);
    if (!ids.length) return;
    await createClient().from("notifications").update({ read_at: new Date().toISOString() }).in("id", ids);
    load();
  }

  return (
    <div className="relative">
      <button
        aria-label={`Notifications, ${unread} unread`}
        onClick={() => setOpen((o) => !o)}
        className="relative rounded-full p-2 hover:bg-gray-100 dark:hover:bg-gray-800"
      >
        <span aria-hidden>🔔</span>
        {unread > 0 && (
          <span className="absolute -right-0.5 -top-0.5 min-w-5 rounded-full bg-red-600 px-1 text-center text-xs font-bold text-white">
            {unread > 99 ? "99+" : unread}
          </span>
        )}
      </button>
      {open && (
        <div className="absolute right-0 z-20 mt-2 w-80 max-w-[90vw] rounded-lg border bg-white p-2 shadow-lg dark:bg-gray-900">
          <div className="flex items-center justify-between px-2 py-1">
            <strong className="text-sm">Notifications</strong>
            <button onClick={markAllRead} className="text-xs text-blue-600">Mark all read</button>
          </div>
          <ul className="max-h-96 overflow-auto">
            {items.length === 0 && <li className="p-3 text-sm text-gray-500">Nothing yet.</li>}
            {items.map((n) => (
              <li key={n.id} className={`rounded p-2 text-sm ${n.read_at ? "opacity-60" : "bg-red-50 dark:bg-red-950"}`}>
                <Link href={`/equipment/${n.equipment_id}`} onClick={() => setOpen(false)}>
                  <span aria-hidden>{n.kind === "failure" ? "🔴 " : "🟢 "}</span>
                  {n.message}
                  <div className="text-xs text-gray-500">{new Date(n.created_at).toLocaleString()}</div>
                </Link>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
