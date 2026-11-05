"use client";

import { openDB, type DBSchema } from "idb";
import { createClient } from "@/lib/supabase/client";

export interface PendingReport {
  clientEventId: string; // also the idempotency key on the server
  userId: string;
  equipmentId: string;
  statusTypeId: string;
  note: string | null;
  reportedAt: string;
  photo: Blob | null;
}

interface QueueDB extends DBSchema {
  reports: { key: string; value: PendingReport };
}

const db = () =>
  openDB<QueueDB>("equipment-queue", 1, {
    upgrade(d) {
      d.createObjectStore("reports", { keyPath: "clientEventId" });
    },
  });

export type SendResult = "sent" | "offline" | "rejected";

/** Shrink a phone photo to ~1280px JPEG so it uploads fast on mobile data. */
export async function compressImage(file: File): Promise<Blob> {
  try {
    const bmp = await createImageBitmap(file);
    const scale = Math.min(1, 1280 / Math.max(bmp.width, bmp.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(bmp.width * scale);
    canvas.height = Math.round(bmp.height * scale);
    canvas.getContext("2d")!.drawImage(bmp, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise<Blob | null>((r) => canvas.toBlob(r, "image/jpeg", 0.7));
    return blob ?? file;
  } catch {
    return file;
  }
}

/** Try to deliver one report. Safe to call repeatedly: the unique client_event_id prevents duplicates. */
export async function sendReport(r: PendingReport): Promise<SendResult> {
  const supabase = createClient();
  try {
    let photoPath: string | null = null;
    if (r.photo) {
      photoPath = `${r.equipmentId}/${r.clientEventId}.jpg`;
      const { error } = await supabase.storage
        .from("failure-photos")
        .upload(photoPath, r.photo, { contentType: "image/jpeg", upsert: true });
      if (error) {
        if (isNetworkError(error)) return "offline";
        photoPath = null; // don't lose the report because of the photo
      }
    }
    const { error } = await supabase.from("status_events").insert({
      client_event_id: r.clientEventId,
      equipment_id: r.equipmentId,
      status_type_id: r.statusTypeId,
      note: r.note,
      photo_path: photoPath,
      reported_at: r.reportedAt,
    });
    if (!error || error.code === "23505") return "sent"; // 23505 = already delivered earlier
    return isNetworkError(error) ? "offline" : "rejected";
  } catch {
    return "offline";
  }
}

function isNetworkError(e: { message?: string; status?: number }) {
  return !navigator.onLine || /fetch|network|load failed/i.test(e.message ?? "") || e.status === 0;
}

export async function queueReport(r: PendingReport) {
  await (await db()).put("reports", r);
}

export async function pendingCount(userId: string) {
  const all = await (await db()).getAll("reports");
  return all.filter((r) => r.userId === userId).length;
}

/** Flush queued reports belonging to the signed-in user. Returns how many were delivered. */
export async function flushQueue(userId: string): Promise<number> {
  const d = await db();
  const items = (await d.getAll("reports")).filter((r) => r.userId === userId);
  let sent = 0;
  for (const item of items) {
    const res = await sendReport(item);
    if (res === "offline") break;
    // "rejected" (e.g. equipment retired or access removed) can never succeed: drop it
    await d.delete("reports", item.clientEventId);
    if (res === "sent") sent++;
  }
  return sent;
}
