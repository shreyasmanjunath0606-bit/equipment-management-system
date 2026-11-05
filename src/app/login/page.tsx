import { Suspense } from "react";
import LoginForm from "./login-form";

export default function LoginPage() {
  return (
    <main className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center gap-6 p-6">
      <div>
        <h1 className="text-2xl font-bold">Equipment Portal</h1>
        <p className="text-sm text-gray-500">Sign in to report or view equipment status.</p>
      </div>
      <Suspense>
        <LoginForm />
      </Suspense>
      <p className="text-xs text-gray-500">
        No account? Ask your plant manager or admin for an invite link.
      </p>
    </main>
  );
}
