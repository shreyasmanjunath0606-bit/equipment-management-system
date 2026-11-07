"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Building2 } from "lucide-react";
import type { Plant } from "@/lib/types";
import { inputClass } from "@/components/ui";
import { cn } from "@/lib/cn";

/** Plant selector that applies immediately (no "Apply" button). */
export default function PlantFilter({ plants, param = "plant" }: { plants: Pick<Plant, "id" | "name">[]; param?: string }) {
  const router = useRouter();
  const pathname = usePathname();
  const sp = useSearchParams();
  return (
    <label className="relative flex items-center">
      <Building2 className="pointer-events-none absolute left-3 size-4 text-muted" />
      <span className="sr-only">Plant</span>
      <select
        value={sp.get(param) ?? ""}
        onChange={(e) => {
          const u = new URLSearchParams(sp);
          if (e.target.value) u.set(param, e.target.value);
          else u.delete(param);
          u.delete("page");
          router.push(`${pathname}${u.size ? `?${u}` : ""}`);
        }}
        className={cn(inputClass, "w-auto min-w-44 pl-9")}
      >
        <option value="">All plants</option>
        {plants.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
      </select>
    </label>
  );
}
