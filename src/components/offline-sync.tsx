"use client";

import { useEffect, useState } from "react";
import { CloudUpload, WifiOff } from "lucide-react";
import { flushQueue, pendingCount } from "@/lib/offline-queue";

/** Delivers reports saved while offline, whenever the phone gets signal again. */
export default function OfflineSync({ userId }: { userId: string }) {
  const [pending, setPending] = useState(0);
  const [online, setOnline] = useState(true);

  useEffect(() => {
    let cancelled = false;
    const run = async () => {
      setOnline(navigator.onLine);
      if (navigator.onLine) await flushQueue(userId);
      if (!cancelled) setPending(await pendingCount(userId));
    };
    run();
    const t = setInterval(run, 15000);
    window.addEventListener("online", run);
    window.addEventListener("offline", run);
    return () => {
      cancelled = true;
      clearInterval(t);
      window.removeEventListener("online", run);
      window.removeEventListener("offline", run);
    };
  }, [userId]);

  if (online && pending === 0) return null;
  return (
    <div role="status" className="flex items-center justify-center gap-2 border-t border-amber-200 bg-amber-50 px-4 py-2 text-center text-sm text-amber-900 dark:border-amber-900 dark:bg-amber-950 dark:text-amber-200">
      {online ? <CloudUpload className="size-4 shrink-0" /> : <WifiOff className="size-4 shrink-0" />}
      {!online ? "You are offline. " : ""}
      {pending > 0 ? `${pending} report(s) waiting to be sent — they will upload automatically.` : "Reports will be saved and sent when you reconnect."}
    </div>
  );
}
