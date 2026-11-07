"use client";

import { Printer } from "lucide-react";
import { buttonClass } from "@/components/ui";

export default function PrintButton() {
  return (
    <button type="button" onClick={() => window.print()} className={buttonClass("primary")}>
      <Printer className="size-4" /> Print label
    </button>
  );
}
