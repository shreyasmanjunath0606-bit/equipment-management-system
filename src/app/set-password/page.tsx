"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { AlertCircle, Loader2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import AuthShell from "@/components/auth-shell";
import { Button, Input, Label } from "@/components/ui";

export default function SetPasswordPage() {
  const router = useRouter();
  const [password, setPassword] = useState("");
  const strength =
    (password.length >= 8 ? 1 : 0) +
    (/[a-z]/.test(password) && /[A-Z]/.test(password) ? 1 : 0) +
    (/\d/.test(password) ? 1 : 0) +
    (/[^A-Za-z0-9]/.test(password) ? 1 : 0);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (password.length < 8) return setError("Use at least 8 characters.");
    setBusy(true);
    const { error } = await createClient().auth.updateUser({ password });
    if (error) {
      setError(error.message);
      setBusy(false);
      return;
    }
    router.replace("/");
    router.refresh();
  }

  return (
    <AuthShell title="Set your password" subtitle="Welcome aboard! You will stay signed in on this device.">
      <form onSubmit={onSubmit} className="flex flex-col gap-4">
        <div>
          <Label htmlFor="new-password">New password</Label>
          <Input
            id="new-password" type="password" required minLength={8} autoComplete="new-password" placeholder="At least 8 characters"
            value={password} onChange={(e) => setPassword(e.target.value)}
            className="h-11 text-base sm:text-sm"
          />
          <div className="mt-2 flex gap-1" aria-hidden>
            {[1, 2, 3, 4].map((i) => (
              <span key={i} className={`h-1 flex-1 rounded-full ${strength >= i ? (strength >= 3 ? "bg-success" : "bg-warning") : "bg-surface-muted"}`} />
            ))}
          </div>
          <p className="mt-1 text-xs text-muted">Use 8+ characters; mixing cases, numbers and symbols makes it stronger.</p>
        </div>
        {error && (
          <div role="alert" className="flex items-start gap-2 rounded-lg border border-danger/30 bg-danger-soft px-3 py-2.5 text-sm text-danger">
            <AlertCircle className="mt-0.5 size-4 shrink-0" /> {error}
          </div>
        )}
        <Button disabled={busy} size="lg" className="mt-2 w-full">
          {busy && <Loader2 className="size-4 animate-spin" />}
          {busy ? "Saving…" : "Save and continue"}
        </Button>
      </form>
    </AuthShell>
  );
}
