import { useConvexAuth } from "convex/react";
import { isSupabaseAuth } from "@/lib/auth/config";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";

type BoundaryProps = { children: React.ReactNode };

function SupabaseAuthGate({
  mode,
  children,
}: BoundaryProps & { mode: "loading" | "auth" | "unauth" }) {
  const { isLoading, session } = useSupabaseAuth();
  const isAuthenticated = !!session;

  if (mode === "loading") {
    if (!isLoading) return null;
    return <>{children}</>;
  }
  if (mode === "auth") {
    if (isLoading || !isAuthenticated) return null;
    return <>{children}</>;
  }
  if (isLoading || isAuthenticated) return null;
  return <>{children}</>;
}

function ConvexAuthGate({
  mode,
  children,
}: BoundaryProps & { mode: "loading" | "auth" | "unauth" }) {
  const { isLoading, isAuthenticated } = useConvexAuth();

  if (mode === "loading") {
    if (!isLoading) return null;
    return <>{children}</>;
  }
  if (mode === "auth") {
    if (isLoading || !isAuthenticated) return null;
    return <>{children}</>;
  }
  if (isLoading || isAuthenticated) return null;
  return <>{children}</>;
}

function AuthGate({
  mode,
  children,
}: BoundaryProps & { mode: "loading" | "auth" | "unauth" }) {
  if (isSupabaseAuth()) {
    return <SupabaseAuthGate mode={mode}>{children}</SupabaseAuthGate>;
  }
  return <ConvexAuthGate mode={mode}>{children}</ConvexAuthGate>;
}

export function AuthLoading({ children }: BoundaryProps) {
  return <AuthGate mode="loading">{children}</AuthGate>;
}

export function Authenticated({ children }: BoundaryProps) {
  return <AuthGate mode="auth">{children}</AuthGate>;
}

export function Unauthenticated({ children }: BoundaryProps) {
  return <AuthGate mode="unauth">{children}</AuthGate>;
}
