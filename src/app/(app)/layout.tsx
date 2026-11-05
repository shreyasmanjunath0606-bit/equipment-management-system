import Link from "next/link";
import { requireUser } from "@/lib/auth";
import NotificationBell from "@/components/notification-bell";
import OfflineSync from "@/components/offline-sync";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const { profile } = await requireUser();
  const isManager = profile.role === "manager" || profile.role === "admin";

  return (
    <>
      <header className="sticky top-0 z-10 border-b bg-background">
        <div className="mx-auto flex max-w-5xl items-center gap-3 px-4 py-2">
          <Link href="/" className="font-bold">Equipment Portal</Link>
          <nav className="flex flex-1 gap-3 overflow-x-auto text-sm">
            {isManager && <Link href="/dashboard">Dashboard</Link>}
            <Link href="/equipment">Equipment</Link>
            <Link href="/history">History</Link>
            {isManager && <Link href="/admin/equipment">Manage</Link>}
            {profile.role === "admin" && <Link href="/admin/users">Users</Link>}
            {profile.role === "admin" && <Link href="/admin/plants">Plants</Link>}
          </nav>
          {isManager && <NotificationBell userId={profile.id} />}
          <form action="/auth/signout" method="post">
            <button className="text-xs text-gray-500 underline" title={profile.email}>Sign out</button>
          </form>
        </div>
        <OfflineSync userId={profile.id} />
      </header>
      <main className="mx-auto w-full max-w-5xl flex-1 p-4">{children}</main>
    </>
  );
}
