"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { compressImage, queueReport, sendReport } from "@/lib/offline-queue";
import type { StatusType } from "@/lib/types";

interface Props {
  userId: string;
  equipment: { id: string; name: string; tag: string; plant: string };
  statusTypes: StatusType[];
}

export default function StatusForm({ userId, equipment, statusTypes }: Props) {
  const router = useRouter();
  const [statusId, setStatusId] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const [photo, setPhoto] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ kind: "ok" | "queued" | "error"; text: string } | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!statusId) return;
    setBusy(true);
    const report = {
      clientEventId: crypto.randomUUID(),
      userId,
      equipmentId: equipment.id,
      statusTypeId: statusId,
      note: note.trim() || null,
      reportedAt: new Date().toISOString(),
      photo: photo ? await compressImage(photo) : null,
    };
    const result = await sendReport(report);
    if (result === "sent") {
      setMessage({ kind: "ok", text: "Reported. Managers have been notified." });
      setTimeout(() => router.replace(`/equipment/${equipment.id}`), 900);
    } else if (result === "offline") {
      await queueReport(report);
      setMessage({ kind: "queued", text: "No signal. Saved on your phone — it will be sent automatically when you're back online." });
      setBusy(false);
    } else {
      setMessage({ kind: "error", text: "Could not save this report. Check that you have access to this equipment." });
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} className="mx-auto flex max-w-md flex-col gap-4">
      <div>
        <h1 className="text-xl font-bold">{equipment.name}</h1>
        <p className="text-sm text-gray-500">{equipment.tag} · {equipment.plant}</p>
      </div>

      <fieldset className="grid grid-cols-2 gap-3">
        <legend className="mb-2 font-semibold">What is the status now?</legend>
        {statusTypes.map((t) => (
          <button
            type="button" key={t.id} onClick={() => setStatusId(t.id)}
            aria-pressed={statusId === t.id}
            className="rounded-xl border-2 px-3 py-5 text-lg font-bold text-white transition"
            style={{
              backgroundColor: t.color,
              borderColor: statusId === t.id ? "#111827" : "transparent",
              opacity: statusId && statusId !== t.id ? 0.45 : 1,
            }}
          >
            {t.label}
          </button>
        ))}
      </fieldset>

      <label className="flex flex-col gap-1">
        <span className="font-semibold">What happened? <span className="font-normal text-gray-500">(optional)</span></span>
        <textarea
          value={note} onChange={(e) => setNote(e.target.value)} rows={3} maxLength={2000}
          placeholder="e.g. Belt snapped, strange noise from motor"
          className="rounded-lg border px-3 py-2 text-base"
        />
      </label>

      <label className="flex flex-col gap-1">
        <span className="font-semibold">Photo <span className="font-normal text-gray-500">(optional)</span></span>
        <input
          type="file" accept="image/*" capture="environment"
          onChange={(e) => setPhoto(e.target.files?.[0] ?? null)}
          className="text-sm"
        />
      </label>

      {message && (
        <p role="status" className={`rounded-lg p-3 text-sm ${message.kind === "ok" ? "bg-green-100 text-green-900" : message.kind === "queued" ? "bg-amber-100 text-amber-900" : "bg-red-100 text-red-900"}`}>
          {message.text}
        </p>
      )}

      <button
        disabled={!statusId || busy || message?.kind === "ok"}
        className="rounded-xl bg-blue-600 px-4 py-4 text-lg font-bold text-white disabled:opacity-50"
      >
        {busy ? "Sending…" : "Submit report"}
      </button>
    </form>
  );
}
