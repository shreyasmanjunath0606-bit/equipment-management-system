"use client";

import { useEffect, useRef } from "react";
import { usePathname, useRouter } from "next/navigation";

/**
 * Drop inside a GET <form>: submits on select change immediately and on text input
 * after a 350ms debounce, so filters apply without an explicit "Filter" button.
 */
export default function AutoSubmit({ delay = 350 }: { delay?: number }) {
  const ref = useRef<HTMLSpanElement>(null);
  const router = useRouter();
  const pathname = usePathname();

  useEffect(() => {
    const form = ref.current?.closest("form");
    if (!form) return;
    let t: ReturnType<typeof setTimeout>;
    const go = () => {
      const u = new URLSearchParams();
      for (const [k, v] of new FormData(form)) if (typeof v === "string" && v) u.set(k, v);
      router.replace(`${pathname}${u.size ? `?${u}` : ""}`, { scroll: false });
    };
    const onChange = (e: Event) => {
      clearTimeout(t);
      if ((e.target as HTMLElement).tagName === "SELECT" || (e.target as HTMLInputElement).type === "date") go();
    };
    const onInput = (e: Event) => {
      if ((e.target as HTMLElement).tagName !== "INPUT") return;
      clearTimeout(t);
      t = setTimeout(go, delay);
    };
    const onSubmit = (e: Event) => { e.preventDefault(); clearTimeout(t); go(); };
    form.addEventListener("change", onChange);
    form.addEventListener("input", onInput);
    form.addEventListener("submit", onSubmit);
    return () => {
      clearTimeout(t);
      form.removeEventListener("change", onChange);
      form.removeEventListener("input", onInput);
      form.removeEventListener("submit", onSubmit);
    };
  }, [router, pathname, delay]);

  return <span ref={ref} hidden />;
}
