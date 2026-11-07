import Link from "next/link";
import { Factory } from "lucide-react";
import { requireUser } from "@/lib/auth";
import NotificationBell from "@/components/notification-bell";
import OfflineSync from "@/components/offline-sync";
import { BottomNav, SidebarNav } from "@/components/app-nav";
import UserMenu from "@/components/user-menu";
import RecoveryRedirect from "@/components/recovery-redirect";

function Logo() {
  return (
    <Link href="/" className="flex items-center gap-2.5">
      <span className="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground shadow-sm">
        <Factory className="size-4" />
      </span>
      <span className="leading-tight">
        <span className="block text-sm font-semibold">Equipment Portal</span>
        <span className="block text-[11px] text-muted">Plant operations</span>
      </span>
    </Link>
  );
}

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const { profile } = await requireUser();
  const isManager = profile.role === "manager" || profile.role === "admin";

  return (
    <div className="flex min-h-screen">
      <RecoveryRedirect />
      {/* Sidebar (desktop) */}
      <aside className="sticky top-0 hidden h-screen w-64 shrink-0 flex-col border-r bg-surface lg:flex print:hidden">
        <div className="flex h-16 items-center border-b px-5">
          <Logo />
        </div>
        <div className="flex-1 overflow-y-auto px-3 py-5">
          <SidebarNav role={profile.role} />
        </div>
        <div className="border-t px-5 py-4 text-[11px] text-muted">v0.1 · Signed in as <span className="capitalize">{profile.role}</span></div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        {/* Top bar */}
        <header className="sticky top-0 z-20 border-b bg-surface/90 backdrop-blur print:hidden">
          <div className="flex h-16 items-center gap-3 px-4 sm:px-6">
            <div className="lg:hidden">
              <Logo />
            </div>
            <div className="flex-1" />
            {isManager && <NotificationBell userId={profile.id} />}
            <UserMenu name={profile.name} email={profile.email} role={profile.role} />
          </div>
          <OfflineSync userId={profile.id} />
        </header>

        <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-6 pb-24 sm:px-6 lg:px-8 lg:pb-8">{children}</main>
      </div>

      <BottomNav role={profile.role} />
    </div>
  );
}
