"use client";

import { AlertOctagon } from "lucide-react";
import { Button, Card, EmptyState } from "@/components/ui";

export default function Error({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <Card>
      <EmptyState
        icon={AlertOctagon}
        title="Something went wrong"
        description={error.digest ? `The page failed to load (ref ${error.digest}).` : "The page failed to load. Please try again."}
        action={<Button onClick={reset}>Try again</Button>}
      />
    </Card>
  );
}
