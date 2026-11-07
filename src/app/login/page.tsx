import { Suspense } from "react";
import AuthShell from "@/components/auth-shell";
import LoginForm from "./login-form";

export default function LoginPage() {
  return (
    <AuthShell
      title="Welcome back"
      subtitle="Sign in to report or view equipment status."
      footer="No account? Ask your plant manager or admin for an invite link."
    >
      <Suspense>
        <LoginForm />
      </Suspense>
    </AuthShell>
  );
}
