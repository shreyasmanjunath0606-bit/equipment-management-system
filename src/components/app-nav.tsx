"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Building2, ClipboardList, History, LayoutDashboard, Users, Wrench, type LucideIcon } from "lucide-react";
import type { Role } from "@/lib/types";
import { cn } from "@/lib/cn";

type Item = { href: string; label: string; icon: LucideIcon; roles: Role[]; group: "main" | "admin" };

const ITEMS: Item[] = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard, roles: ["manager", "admin"], group: "main" },
  { href: "/equipment", label: "Equipment", icon: Wrench, roles: ["worker", "manager", "admin"], group: "main" },
  { href: "/history", label: "History", icon: History, roles: ["worker", "manager", "admin"], group: "main" },
  { href: "/admin/equipment", label: "Manage equipment", icon: ClipboardList, roles: ["manager", "admin"], group: "admin" },
  { href: "/admin/users", label: "Users", icon: Users, roles: ["admin"], group: "admin" },
  { href: "/admin/plants", label: "Plants", icon: Building2, roles: ["admin"], group: "admin" },
];

function useItems(role: Role) {
  const pathname = usePathname();
  const items = ITEMS.filter((i) => i.roles.includes(role));
  const isActive = (href: string) => pathname === href || pathname.startsWith(href + "/");
  return { items, isActive };
}

/** Desktop sidebar navigation. */
export function SidebarNav({ role }: { role: Role }) {
  const { items, isActive } = useItems(role);
  const groups: { key: Item["group"]; label: string | null }[] = [
    { key: "main", label: null },
    { key: "admin", label: "Administration" },
  ];
  return (
    <nav className="flex flex-col gap-6">
      {groups.map(({ key, label }) => {
        const list = items.filter((i) => i.group === key);
        if (!list.length) return null;
        return (
          <div key={key}>
            {label && <p className="mb-2 px-3 text-[11px] font-semibold uppercase tracking-wider text-muted">{label}</p>}
            <ul className="flex flex-col gap-0.5">
              {list.map(({ href, label, icon: Icon }) => (
                <li key={href}>
                  <Link
                    href={href}
                    aria-current={isActive(href) ? "page" : undefined}
                    className={cn(
                      "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
                      isActive(href) ? "bg-primary-soft text-primary" : "text-muted hover:bg-surface-muted hover:text-foreground",
                    )}
                  >
                    <Icon className="size-4" />
                    {label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        );
      })}
    </nav>
  );
}

/** Mobile bottom tab bar (main items only). */
export function BottomNav({ role }: { role: Role }) {
  const { items, isActive } = useItems(role);
  const list = items.filter((i) => i.group === "main");
  return (
    <nav className="fixed inset-x-0 bottom-0 z-30 border-t bg-surface/95 pb-[env(safe-area-inset-bottom)] backdrop-blur lg:hidden print:hidden">
      <ul className="flex">
        {list.map(({ href, label, icon: Icon }) => (
          <li key={href} className="flex-1">
            <Link
              href={href}
              aria-current={isActive(href) ? "page" : undefined}
              className={cn(
                "flex flex-col items-center gap-1 py-2.5 text-[11px] font-medium",
                isActive(href) ? "text-primary" : "text-muted",
              )}
            >
              <Icon className="size-5" />
              {label}
            </Link>
          </li>
        ))}
      </ul>
    </nav>
  );
}
