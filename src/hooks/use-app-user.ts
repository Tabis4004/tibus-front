import { useContext } from "react";
import { AppUserContext } from "@/components/providers/app-user-context.ts";
import {
  APP_USER_REFRESH_DONE_EVENT,
  APP_USER_REFRESH_EVENT,
} from "@/hooks/app-user-events.ts";
import { useAppUserState, type AppUserState } from "@/hooks/use-app-user-state.ts";

export { APP_USER_REFRESH_DONE_EVENT, APP_USER_REFRESH_EVENT } from "@/hooks/app-user-events.ts";

export const SELLER_ROLE_NAMES = [
  "vendeur",
  "vendeur_gare",
  "chauffeur",
  "vendeur_independant",
  "vendeur_reseau",
  "vendeur_master",
] as const;

export const THIRD_PARTY_SELLER_ROLE_NAMES = [
  "vendeur_independant",
  "vendeur_reseau",
  "vendeur_master",
] as const;

export const SELLER_ACCESS_ROLE_NAMES = [
  ...SELLER_ROLE_NAMES,
  "owner",
] as const;

export const MERCHANT_AGENT_CTA_BLOCKING_ROLES = [
  ...SELLER_ACCESS_ROLE_NAMES,
  "super_admin",
] as const;

export const MERCHANT_AGENT_CTA_BLOCKING_APPLICATION_STATUSES = [
  "pending",
  "success",
  "approved",
  "accepted",
] as const;

export function hasAnyRole(roles: readonly string[], roleNames: readonly string[]) {
  return roleNames.some((roleName) => roles.includes(roleName));
}

export type AppUserProfile = {
  id: string;
  firstName: string;
  lastName: string;
  email: string | null;
  username: string;
  phone: string | null;
  countryId: string;
  profileCompleted: boolean;
  onboardingCompleted: boolean;
};

export function normalizeRoleForUi(role: string): string {
  if (role === "super_admin") return "superadmin";
  return role;
}

export function refreshAppUser() {
  window.dispatchEvent(new Event(APP_USER_REFRESH_EVENT));
}

export function refreshAppUserAsync(timeoutMs = 10_000): Promise<void> {
  return new Promise((resolve, reject) => {
    const timer = window.setTimeout(() => {
      cleanup();
      reject(new Error("Profile refresh timeout"));
    }, timeoutMs);

    const onDone = () => {
      cleanup();
      resolve();
    };

    const cleanup = () => {
      window.clearTimeout(timer);
      window.removeEventListener(APP_USER_REFRESH_DONE_EVENT, onDone);
    };

    window.addEventListener(APP_USER_REFRESH_DONE_EVENT, onDone);
    window.dispatchEvent(new Event(APP_USER_REFRESH_EVENT));
  });
}

export type { AppUserState };

export function useAppUser(): AppUserState {
  const context = useContext(AppUserContext);
  if (context) return context;
  return useAppUserState();
}
