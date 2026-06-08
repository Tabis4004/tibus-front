import { ConvexProviderWithHerculesAuth } from "@usehercules/auth/convex-react";
import { ConvexProvider as BaseConvexProvider, ConvexReactClient } from "convex/react";
import { isSupabaseAuth } from "@/lib/auth/config";

const convexUrl = import.meta.env.VITE_CONVEX_URL ?? "http://localhost:3000";
const convex = new ConvexReactClient(convexUrl);

export function ConvexProvider({ children }: { children: React.ReactNode }) {
  if (isSupabaseAuth()) {
    return <BaseConvexProvider client={convex}>{children}</BaseConvexProvider>;
  }

  return (
    <ConvexProviderWithHerculesAuth client={convex}>
      {children}
    </ConvexProviderWithHerculesAuth>
  );
}
