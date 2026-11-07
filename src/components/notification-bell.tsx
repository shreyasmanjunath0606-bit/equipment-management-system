"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { AlertTriangle, Bell, BellOff, CheckCircle2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import type { NotificationRow } from "@/lib/types";
import { timeAgo } from "@/components/status-badge";
import { cn } from "@/lib/cn";

export default function NotificationBell({ userId }: { userId: string }) {
  const [items, setItems] = useState<NotificationRow[]>([]);
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

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

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => { if (!ref.current?.contains(e.target as Node)) setOpen(false); };
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setOpen(false); };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => { document.removeEventListener("mousedown", onDown); document.removeEventListener("keydown", onKey); };
  }, [open]);

  const unread = items.filter((i) => !i.read_at).length;

  async function markAllRead() {
    const ids = items.filter((i) => !i.read_at).map((i) => i.id);
    if (!ids.length) return;
    await createClient().from("notifications").update({ read_at: new Date().toISOString() }).in("id", ids);
    load();
  }

  return (
    <div ref={ref} className="relative">
      <button
        aria-label={`Notifications, ${unread} unread`}
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        className="relative flex size-9 items-center justify-center rounded-full text-muted hover:bg-surface-muted hover:text-foreground"
      >
        <Bell className="size-5" />
        {unread > 0 && (
          <span className="absolute right-0.5 top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-danger px-1 text-[10px] font-semibold text-white ring-2 ring-surface">
            {unread > 99 ? "99+" : unread}
          </span>
        )}
      </button>
      {open && (
        <div className="absolute right-0 z-40 mt-2 w-96 max-w-[calc(100vw-2rem)] overflow-hidden rounded-xl border bg-surface shadow-lg">
          <div className="flex items-center justify-between border-b px-4 py-3">
            <strong className="text-sm font-semibold">Notifications</strong>
            {unread > 0 && (
              <button onClick={markAllRead} className="text-xs font-medium text-primary hover:underline">Mark all as read</button>
            )}
          </div>
          <ul className="max-h-96 divide-y overflow-auto">
            {items.length === 0 && (
              <li className="flex flex-col items-center gap-2 px-4 py-10 text-sm text-muted">
                <BellOff className="size-5" /> You&apos;re all caught up.
              </li>
            )}
            {items.map((n) => {
              const failure = n.kind === "failure";
              const Icon = failure ? AlertTriangle : CheckCircle2;
              return (
                <li key={n.id}>
                  <Link
                    href={`/equipment/${n.equipment_id}`}
                    onClick={() => setOpen(false)}
                    className={cn("flex gap-3 px-4 py-3 hover:bg-surface-muted", !n.read_at && "bg-primary-soft/40")}
                  >
                    <span className={cn("mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full", failure ? "bg-danger-soft text-danger" : "bg-success/10 text-success")}>
                      <Icon className="size-4" />
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className={cn("block text-sm", !n.read_at && "font-medium")}>{n.message}</span>
                      <span className="text-xs text-muted">{timeAgo(n.created_at)}</span>
                    </span>
                    {!n.read_at && <span className="mt-2 size-2 shrink-0 rounded-full bg-primary" />}
                  </Link>
                </li>
              );
            })}
          </ul>
        </div>
      )}
    </div>
  );
}
