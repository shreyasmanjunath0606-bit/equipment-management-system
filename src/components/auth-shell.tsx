import type { ReactNode } from "react";
import { Activity, BellRing, Factory, QrCode, WifiOff } from "lucide-react";

const FEATURES = [
  { icon: QrCode, text: "Scan a QR tag to report in seconds" },
  { icon: BellRing, text: "Managers are alerted the moment something fails" },
  { icon: WifiOff, text: "Works offline on the shop floor" },
  { icon: Activity, text: "Live status across every plant" },
];

export default function AuthShell({ title, subtitle, children, footer }: { title: string; subtitle: string; children: ReactNode; footer?: ReactNode }) {
  return (
    <div className="grid min-h-dvh lg:grid-cols-2">
      {/* Brand panel */}
      <aside className="relative hidden overflow-hidden bg-gradient-to-br from-blue-700 via-blue-600 to-indigo-700 p-12 text-white lg:flex lg:flex-col">
        <div className="pointer-events-none absolute -right-24 -top-24 size-96 rounded-full bg-white/10 blur-3xl" />
        <div className="pointer-events-none absolute -bottom-32 -left-16 size-96 rounded-full bg-indigo-400/20 blur-3xl" />
        <div className="relative flex items-center gap-3">
          <span className="flex size-10 items-center justify-center rounded-xl bg-white/15 ring-1 ring-white/25">
            <Factory className="size-5" />
          </span>
          <span className="text-lg font-semibold">Equipment Portal</span>
        </div>
        <div className="relative mt-auto max-w-md">
          <h2 className="text-3xl font-semibold leading-tight tracking-tight">Keep every machine running — across every plant.</h2>
          <ul className="mt-8 flex flex-col gap-4">
            {FEATURES.map(({ icon: Icon, text }) => (
              <li key={text} className="flex items-center gap-3 text-blue-50">
                <span className="flex size-8 items-center justify-center rounded-lg bg-white/10"><Icon className="size-4" /></span>
                {text}
              </li>
            ))}
          </ul>
        </div>
        <p className="relative mt-12 text-xs text-blue-100/70">© {new Date().getFullYear()} Plant operations</p>
      </aside>

      {/* Form panel */}
      <main className="flex items-center justify-center bg-background p-6">
        <div className="w-full max-w-sm">
          <div className="mb-8 flex items-center gap-2.5 lg:hidden">
            <span className="flex size-9 items-center justify-center rounded-lg bg-primary text-primary-foreground"><Factory className="size-4" /></span>
            <span className="font-semibold">Equipment Portal</span>
          </div>
          <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
          <p className="mt-1.5 text-sm text-muted">{subtitle}</p>
          <div className="mt-8">{children}</div>
          {footer && <div className="mt-8 border-t pt-6 text-xs text-muted">{footer}</div>}
        </div>
      </main>
    </div>
  );
}
