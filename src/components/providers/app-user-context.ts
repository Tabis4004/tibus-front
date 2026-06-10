import { createContext } from "react";
import type { AppUserState } from "@/hooks/use-app-user-state.ts";

export const AppUserContext = createContext<AppUserState | null>(null);
