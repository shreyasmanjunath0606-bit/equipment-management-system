"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

/**
 * Supabase's default (locked) recovery/invite e-mails land on the site with
 * `#access_token=...&type=recovery`. If the person is already signed in, the app opens
 * normally and nobody asks for a new password — so send them to /set-password.
 */
export default function RecoveryRedirect() {
  const router = useRouter();

  useEffect(() => {
    const hash = window.location.hash;
    if (!/type=(recovery|invite)/.test(hash)) return;
    const supabase = createClient();
    const { data } = supabase.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY" || event === "SIGNED_IN") {
        history.replaceState(null, "", window.location.pathname); // drop the token from the URL
        router.replace("/set-password");
      }
    });
    return () => data.subscription.unsubscribe();
  }, [router]);

  return null;
}
