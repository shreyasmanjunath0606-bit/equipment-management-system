"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { KeyRound, LogOut, Moon, Settings, Sun } from "lucide-react";
import type { Role } from "@/lib/types";

function initials(name: string, email: string) {
  const src = name?.trim() || email;
  const parts = src.split(/[\s@.]+/).filter(Boolean);
  return ((parts[0]?.[0] ?? "") + (parts[1]?.[0] ?? "")).toUpperCase() || "?";
}

export default function UserMenu({ name, email, role }: { name: string; email: string; role: Role }) {
  const [open, setOpen] = useState(false);
  const [dark, setDark] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const t = setTimeout(() => setDark(document.documentElement.dataset.theme === "dark" ||
      (!document.documentElement.dataset.theme && matchMedia("(prefers-color-scheme: dark)").matches)), 0);
    const onDown = (e: MouseEvent) => { if (!ref.current?.contains(e.target as Node)) setOpen(false); };
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setOpen(false); };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => { clearTimeout(t); document.removeEventListener("mousedown", onDown); document.removeEventListener("keydown", onKey); };
  }, []);

  function toggleTheme() {
    const next = dark ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    try { localStorage.setItem("theme", next); } catch {}
    setDark(!dark);
  }

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="menu"
        aria-expanded={open}
        className="flex items-center gap-2 rounded-full p-0.5 pr-2 hover:bg-surface-muted"
      >
        <span className="flex size-8 items-center justify-center rounded-full bg-primary text-xs font-semibold text-primary-foreground">
          {initials(name, email)}
        </span>
        <span className="hidden text-left leading-tight sm:block">
          <span className="block text-sm font-medium">{name || email}</span>
          <span className="block text-[11px] capitalize text-muted">{role}</span>
        </span>
      </button>
      {open && (
        <div role="menu" className="absolute right-0 z-40 mt-2 w-60 overflow-hidden rounded-xl border bg-surface shadow-lg">
          <div className="border-b px-4 py-3">
            <p className="truncate text-sm font-medium">{name || "Signed in"}</p>
            <p className="truncate text-xs text-muted">{email}</p>
          </div>
          <div className="p-1">
            <button role="menuitem" onClick={toggleTheme} className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-surface-muted">
              {dark ? <Sun className="size-4" /> : <Moon className="size-4" />}
              {dark ? "Light mode" : "Dark mode"}
            </button>
            <Link role="menuitem" href="/set-password" onClick={() => setOpen(false)} className="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-surface-muted">
              <KeyRound className="size-4" /> Change password
            </Link>
            {role === "admin" && (
              <Link role="menuitem" href="/admin/users" onClick={() => setOpen(false)} className="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-surface-muted">
                <Settings className="size-4" /> Administration
              </Link>
            )}
            <form action="/auth/signout" method="post">
              <button role="menuitem" className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-danger hover:bg-danger-soft">
                <LogOut className="size-4" /> Sign out
              </button>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
