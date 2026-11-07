"use client";

import { useRef, type ReactNode } from "react";
import { useFormStatus } from "react-dom";
import { AlertTriangle, Loader2, X } from "lucide-react";
import { buttonClass } from "@/components/ui";

type Variant = Parameters<typeof buttonClass>[0];
type Size = Parameters<typeof buttonClass>[1];

/** Submit button that shows a spinner while its server-action form is pending. */
export function SubmitButton({ children, pendingText, variant = "primary", size = "md", className }: { children: ReactNode; pendingText?: string; variant?: Variant; size?: Size; className?: string }) {
  const { pending } = useFormStatus();
  return (
    <button disabled={pending} className={buttonClass(variant, size, className)}>
      {pending && <Loader2 className="size-4 animate-spin" />}
      {pending ? pendingText ?? children : children}
    </button>
  );
}

/** Button that asks for confirmation in a dialog before submitting its parent form. */
export function ConfirmButton({ children, title, description, confirmLabel = "Confirm", variant = "secondary", size = "sm", tone = "danger" }: {
  children: ReactNode; title: string; description: string; confirmLabel?: string; variant?: Variant; size?: Size; tone?: "danger" | "primary";
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const btn = useRef<HTMLButtonElement>(null);
  const { pending } = useFormStatus();
  return (
    <>
      <button ref={btn} type="button" disabled={pending} onClick={() => ref.current?.showModal()} className={buttonClass(variant, size)}>
        {pending && <Loader2 className="size-3.5 animate-spin" />}
        {children}
      </button>
      <dialog ref={ref} onClick={(e) => { if (e.target === ref.current) ref.current?.close(); }}
        className="m-auto w-[min(92vw,26rem)] rounded-xl border bg-surface p-0 text-foreground shadow-xl backdrop:bg-black/50">
        <div className="flex gap-4 p-6">
          <span className={`flex size-10 shrink-0 items-center justify-center rounded-full ${tone === "danger" ? "bg-danger-soft text-danger" : "bg-primary-soft text-primary"}`}>
            <AlertTriangle className="size-5" />
          </span>
          <div>
            <h3 className="font-semibold">{title}</h3>
            <p className="mt-1 text-sm text-muted">{description}</p>
          </div>
        </div>
        <div className="flex justify-end gap-2 border-t bg-surface-muted/50 px-6 py-3">
          <button type="button" onClick={() => ref.current?.close()} className={buttonClass("secondary")}>Cancel</button>
          <button
            type="button"
            onClick={() => { ref.current?.close(); btn.current?.form?.requestSubmit(); }}
            className={buttonClass(tone === "danger" ? "danger" : "primary")}
          >
            {confirmLabel}
          </button>
        </div>
      </dialog>
    </>
  );
}

/** Trigger + modal dialog. Closes itself when a form inside it is submitted. */
export function Modal({ trigger, title, description, children, triggerVariant = "primary" }: {
  trigger: ReactNode; title: string; description?: string; children: ReactNode; triggerVariant?: Variant;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  return (
    <>
      <button type="button" onClick={() => ref.current?.showModal()} className={buttonClass(triggerVariant)}>{trigger}</button>
      <dialog
        ref={ref}
        onClick={(e) => { if (e.target === ref.current) ref.current?.close(); }}
        onSubmit={() => setTimeout(() => ref.current?.close(), 50)}
        className="m-auto w-[min(94vw,36rem)] rounded-xl border bg-surface p-0 text-foreground shadow-xl backdrop:bg-black/50"
      >
        <div className="flex items-start justify-between border-b px-6 py-4">
          <div>
            <h3 className="font-semibold">{title}</h3>
            {description && <p className="mt-0.5 text-sm text-muted">{description}</p>}
          </div>
          <button type="button" onClick={() => ref.current?.close()} aria-label="Close" className="rounded-md p-1 text-muted hover:bg-surface-muted hover:text-foreground">
            <X className="size-4" />
          </button>
        </div>
        <div className="p-6">{children}</div>
      </dialog>
    </>
  );
}
