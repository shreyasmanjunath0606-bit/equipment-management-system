"use client";

import { useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

const ERRORS: Record<string, string> = {
  deactivated: "Your account has been deactivated. Contact your manager.",
  invalid_link: "That link is invalid or expired. Ask for a new invite.",
};

function safeNext(next: string | null) {
  return next && next.startsWith("/") && !next.startsWith("//") && !next.startsWith("/\\") ? next : "/";
}

export default function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(ERRORS[params.get("error") ?? ""] ?? null);
  const [busy, setBusy] = useState(false);

  // Supabase invite / password-recovery e-mail links come back as /#access_token=...&type=invite.
  // The browser client reads that fragment and creates the session; then we send the person on.
  useEffect(() => {
    const hash = window.location.hash;
    if (!hash.includes("access_token=")) return;
    const needsPassword = /type=(invite|recovery)/.test(hash);
    const supabase = createClient();
    const { data } = supabase.auth.onAuthStateChange((event, session) => {
      if (session && (event === "SIGNED_IN" || event === "INITIAL_SESSION")) {
        router.replace(needsPassword ? "/set-password" : "/");
        router.refresh();
      }
    });
    return () => data.subscription.unsubscribe();
  }, [router]);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error } = await createClient().auth.signInWithPassword({ email, password });
    if (error) {
      setError("Wrong email or password.");
      setBusy(false);
      return;
    }
    router.replace(safeNext(params.get("next")));
    router.refresh();
  }

  return (
    <form onSubmit={onSubmit} className="flex flex-col gap-3">
      <input
        type="email" required autoComplete="email" placeholder="Email" value={email}
        onChange={(e) => setEmail(e.target.value)}
        className="rounded-lg border px-4 py-3 text-base"
      />
      <input
        type="password" required autoComplete="current-password" placeholder="Password" value={password}
        onChange={(e) => setPassword(e.target.value)}
        className="rounded-lg border px-4 py-3 text-base"
      />
      {error && <p role="alert" className="text-sm text-red-600">{error}</p>}
      <button disabled={busy} className="rounded-lg bg-blue-600 px-4 py-3 font-semibold text-white disabled:opacity-60">
        {busy ? "Signing in…" : "Sign in"}
      </button>
    </form>
  );
}
