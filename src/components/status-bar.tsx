import type { StatusType } from "@/lib/types";

export type Segment = { status: StatusType | null; count: number };

/** Horizontal part-to-whole bar: 2px surface gaps between segments, hover title per segment. */
export function StatusBar({ segments, height = "h-3", label }: { segments: Segment[]; height?: string; label: string }) {
  const total = segments.reduce((s, x) => s + x.count, 0);
  const visible = segments.filter((s) => s.count > 0);
  if (total === 0) return <div className={`${height} w-full rounded-full bg-surface-muted`} aria-label={`${label}: no equipment`} />;
  return (
    <div role="img" aria-label={`${label}: ${visible.map((s) => `${s.status?.label ?? "No status"} ${s.count}`).join(", ")}`} className={`flex ${height} w-full gap-[2px] overflow-hidden rounded-full`}>
      {visible.map((s, i) => (
        <div
          key={s.status?.id ?? "none"}
          title={`${s.status?.label ?? "No status yet"}: ${s.count} (${Math.round((s.count / total) * 100)}%)`}
          className={`h-full transition-opacity hover:opacity-80 ${i === 0 ? "rounded-l-full" : ""} ${i === visible.length - 1 ? "rounded-r-full" : ""}`}
          style={{ width: `${(s.count / total) * 100}%`, backgroundColor: s.status?.color ?? "var(--muted)", minWidth: 4 }}
        />
      ))}
    </div>
  );
}

/** Legend that doubles as the data table: swatch + label + count + %. */
export function StatusLegend({ segments, hrefFor }: { segments: Segment[]; hrefFor?: (s: Segment) => string }) {
  const total = segments.reduce((s, x) => s + x.count, 0) || 1;
  return (
    <ul className="grid grid-cols-1 gap-x-6 gap-y-2 sm:grid-cols-2">
      {segments.map((s) => {
        const body = (
          <>
            <span className="size-2.5 shrink-0 rounded-sm" style={{ backgroundColor: s.status?.color ?? "var(--muted)" }} />
            <span className="flex-1 truncate">{s.status?.label ?? "No status yet"}</span>
            <span className="font-medium tabular-nums">{s.count}</span>
            <span className="w-10 text-right text-xs tabular-nums text-muted">{Math.round((s.count / total) * 100)}%</span>
          </>
        );
        return (
          <li key={s.status?.id ?? "none"}>
            {hrefFor ? (
              <a href={hrefFor(s)} className="-mx-2 flex items-center gap-2 rounded-md px-2 py-1 text-sm hover:bg-surface-muted">{body}</a>
            ) : (
              <div className="flex items-center gap-2 py-1 text-sm">{body}</div>
            )}
          </li>
        );
      })}
    </ul>
  );
}
