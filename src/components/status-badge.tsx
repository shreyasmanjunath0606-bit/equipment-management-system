import type { StatusType } from "@/lib/types";

export function StatusBadge({ status }: { status: StatusType | undefined | null }) {
  if (!status) {
    return <span className="rounded-full bg-gray-200 px-2 py-0.5 text-xs text-gray-700">No status yet</span>;
  }
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold text-white"
      style={{ backgroundColor: status.color }}
    >
      {status.label}
    </span>
  );
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
