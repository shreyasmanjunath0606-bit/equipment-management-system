"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { AlertCircle, Camera, CheckCircle2, CloudOff, Loader2, X } from "lucide-react";
import { compressImage, queueReport, sendReport } from "@/lib/offline-queue";
import type { StatusType } from "@/lib/types";
import { Button, Card, Label, Textarea } from "@/components/ui";
import { cn } from "@/lib/cn";

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
  const [preview, setPreview] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<{ kind: "ok" | "queued" | "error"; text: string } | null>(null);

  useEffect(() => {
    if (!photo) return;
    const url = URL.createObjectURL(photo);
    const t = setTimeout(() => setPreview(url), 0);
    return () => { clearTimeout(t); URL.revokeObjectURL(url); };
  }, [photo]);

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

  const selected = statusTypes.find((t) => t.id === statusId);
  const msgStyles = {
    ok: { cls: "border-success/30 bg-success/10 text-success", Icon: CheckCircle2 },
    queued: { cls: "border-warning/30 bg-warning/10 text-warning", Icon: CloudOff },
    error: { cls: "border-danger/30 bg-danger-soft text-danger", Icon: AlertCircle },
  };

  return (
    <form onSubmit={submit} className="mx-auto flex max-w-xl flex-col gap-6">
      <div>
        <p className="text-xs font-medium uppercase tracking-wider text-primary">Report status</p>
        <h1 className="mt-1 text-2xl font-semibold tracking-tight">{equipment.name}</h1>
        <p className="mt-1 text-sm text-muted"><span className="font-mono">{equipment.tag}</span> · {equipment.plant}</p>
      </div>

      <Card className="p-5">
        <fieldset>
          <legend className="mb-3 text-sm font-semibold">What is the status now?</legend>
          <div className="grid grid-cols-2 gap-3">
            {statusTypes.map((t) => {
              const active = statusId === t.id;
              return (
                <button
                  type="button" key={t.id} onClick={() => setStatusId(t.id)}
                  aria-pressed={active}
                  className={cn(
                    "relative flex min-h-20 flex-col items-start justify-between gap-2 rounded-xl border-2 p-4 text-left transition",
                    active ? "shadow-md" : "border-border hover:border-muted/50 hover:bg-surface-muted",
                  )}
                  style={active ? { borderColor: t.color, backgroundColor: `color-mix(in srgb, ${t.color} 10%, transparent)` } : undefined}
                >
                  <span className="flex w-full items-center justify-between">
                    <span className="size-3.5 rounded-full" style={{ backgroundColor: t.color }} />
                    {active && <CheckCircle2 className="size-5" style={{ color: t.color }} />}
                  </span>
                  <span className="text-base font-semibold">{t.label}</span>
                  {t.is_failure && <span className="text-[11px] text-muted">Alerts managers</span>}
                </button>
              );
            })}
          </div>
        </fieldset>
      </Card>

      <Card className="flex flex-col gap-5 p-5">
        <div>
          <Label htmlFor="note" className="text-sm font-semibold text-foreground">What happened? <span className="font-normal text-muted">(optional)</span></Label>
          <Textarea
            id="note" value={note} onChange={(e) => setNote(e.target.value)} rows={3} maxLength={2000}
            placeholder="e.g. Belt snapped, strange noise from motor"
            className="text-base sm:text-sm"
          />
          <p className="mt-1 text-right text-[11px] text-muted">{note.length}/2000</p>
        </div>

        <div>
          <span className="mb-1.5 block text-sm font-semibold">Photo <span className="font-normal text-muted">(optional)</span></span>
          {preview && photo ? (
            <div className="relative w-fit">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={preview} alt="Selected photo preview" className="max-h-48 rounded-lg border object-cover" />
              <button type="button" onClick={() => { setPhoto(null); setPreview(null); }} aria-label="Remove photo"
                className="absolute -right-2 -top-2 rounded-full border bg-surface p-1 shadow hover:bg-surface-muted">
                <X className="size-3.5" />
              </button>
            </div>
          ) : (
            <label className="flex cursor-pointer flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed px-4 py-8 text-center transition hover:border-primary hover:bg-primary-soft/40">
              <span className="flex size-10 items-center justify-center rounded-full bg-primary-soft text-primary"><Camera className="size-5" /></span>
              <span className="text-sm font-medium">Take or upload a photo</span>
              <span className="text-xs text-muted">Helps maintenance diagnose faster</span>
              <input
                type="file" accept="image/*" capture="environment" className="sr-only"
                onChange={(e) => setPhoto(e.target.files?.[0] ?? null)}
              />
            </label>
          )}
        </div>
      </Card>

      {message && (() => {
        const { cls, Icon } = msgStyles[message.kind];
        return (
          <div role="status" className={cn("flex items-start gap-2 rounded-lg border px-4 py-3 text-sm font-medium", cls)}>
            <Icon className="mt-0.5 size-4 shrink-0" /> {message.text}
          </div>
        );
      })()}

      <div className="sticky bottom-20 z-10 lg:bottom-4">
        <Button disabled={!statusId || busy || message?.kind === "ok"} size="lg" className="h-12 w-full text-base shadow-lg">
          {busy && <Loader2 className="size-5 animate-spin" />}
          {busy ? "Sending…" : selected ? `Submit — ${selected.label}` : "Select a status"}
        </Button>
      </div>
    </form>
  );
}
