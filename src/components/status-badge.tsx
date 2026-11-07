import type { StatusType } from "@/lib/types";
import { cn } from "@/lib/cn";

/**
 * Status colours come from the database, so render them as a soft tint + dot
 * (readable on any colour) instead of white text on a solid block.
 */
export function StatusBadge({ status, className }: { status: StatusType | undefined | null; className?: string }) {
  if (!status) {
    return (
      <span className={cn("inline-flex items-center gap-1.5 rounded-full border bg-surface-muted px-2.5 py-0.5 text-xs font-medium text-muted", className)}>
        <span className="size-1.5 rounded-full bg-muted" />
        No status yet
      </span>
    );
  }
  return (
    <span
      className={cn("inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-medium text-foreground", className)}
      style={{
        backgroundColor: `color-mix(in srgb, ${status.color} 14%, transparent)`,
        borderColor: `color-mix(in srgb, ${status.color} 35%, transparent)`,
      }}
    >
      <span className="size-1.5 rounded-full" style={{ backgroundColor: status.color }} />
      {status.label}
    </span>
  );
}

/** Black or white text, whichever reads better on the given hex colour. */
export function readableText(hex: string): string {
  const h = hex.replace("#", "");
  const full = h.length === 3 ? h.split("").map((c) => c + c).join("") : h;
  const n = parseInt(full, 16);
  if (Number.isNaN(n)) return "#fff";
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return lum > 0.4 ? "#0f172a" : "#ffffff";
}

export function timeAgo(iso: string | null): string {
  if (!iso) return "—";
  const s = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 1000));
  if (s < 60) return "just now";
  const m = Math.floor(s / 60);
  if (m < 60) return `${m} min ago`;
  const h = Math.floor(m / 60);
  if (h < 48) return `${h} h ago`;
  return `${Math.floor(h / 24)} days ago`;
}

export function formatDateTime(iso: string, timeZone?: string): string {
  return new Date(iso).toLocaleString(undefined, { timeZone, dateStyle: "medium", timeStyle: "short" });
}
