"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function SetPasswordPage() {
  const router = useRouter();
  const [password, setPassword] = useState("");
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
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-4 p-6">
      <h1 className="text-2xl font-bold">Welcome — set your password</h1>
      <p className="text-sm text-gray-500">You will stay signed in on this phone.</p>
      <form onSubmit={onSubmit} className="flex flex-col gap-3">
        <input
          type="password" required minLength={8} autoComplete="new-password" placeholder="New password"
          value={password} onChange={(e) => setPassword(e.target.value)}
          className="rounded-lg border px-4 py-3 text-base"
        />
        {error && <p role="alert" className="text-sm text-red-600">{error}</p>}
        <button disabled={busy} className="rounded-lg bg-blue-600 px-4 py-3 font-semibold text-white disabled:opacity-60">
          {busy ? "Saving…" : "Save and continue"}
        </button>
      </form>
    </main>
  );
}
