import { isSupabaseAuth } from "@/lib/auth/config";
import { AuthProvider as HerculesAuthProvider } from "./auth.tsx";
import { ConvexProvider } from "./convex.tsx";
import { QueryClientProvider } from "./query-client.tsx";
import { AppUserProvider } from "./app-user-provider.tsx";
import { SupabaseAuthProvider } from "./supabase-auth.tsx";
import { ThemeProvider } from "./theme.tsx";
import { Toaster } from "../ui/sonner.tsx";
import { TooltipProvider } from "../ui/tooltip.tsx";

function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <ConvexProvider>
      <QueryClientProvider>
        <TooltipProvider>
          <ThemeProvider>
            <Toaster />
            {children}
          </ThemeProvider>
        </TooltipProvider>
      </QueryClientProvider>
    </ConvexProvider>
  );
}

export function DefaultProviders({ children }: { children: React.ReactNode }) {
  if (isSupabaseAuth()) {
    return (
      <SupabaseAuthProvider>
        <AppUserProvider>
          <AppShell>{children}</AppShell>
        </AppUserProvider>
      </SupabaseAuthProvider>
    );
  }

  return (
    <HerculesAuthProvider>
      <AppShell>{children}</AppShell>
    </HerculesAuthProvider>
  );
}
