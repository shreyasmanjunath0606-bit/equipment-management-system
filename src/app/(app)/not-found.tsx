import Link from "next/link";
import { SearchX } from "lucide-react";
import { Card, EmptyState, buttonClass } from "@/components/ui";

export default function NotFound() {
  return (
    <Card>
      <EmptyState
        icon={SearchX}
        title="Not found"
        description="This item doesn't exist, was retired, or belongs to a plant you can't access."
        action={<Link href="/equipment" className={buttonClass("secondary")}>Back to equipment</Link>}
      />
    </Card>
  );
}
