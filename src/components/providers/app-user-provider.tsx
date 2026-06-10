import type { ReactNode } from "react";
import { useAppUserState } from "@/hooks/use-app-user-state.ts";
import { AppUserContext } from "@/components/providers/app-user-context.ts";

export function AppUserProvider({ children }: { children: ReactNode }) {
  const value = useAppUserState();
  return <AppUserContext.Provider value={value}>{children}</AppUserContext.Provider>;
}
