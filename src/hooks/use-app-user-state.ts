import { useCallback, useEffect, useMemo, useState } from "react";
import { isSupabaseAuth } from "@/lib/auth/config";
import { resolveAdminSandboxRoles } from "@/lib/auth/admin-sandbox.ts";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { supabase } from "@/lib/supabase";
import {
  APP_USER_REFRESH_DONE_EVENT,
  APP_USER_REFRESH_EVENT,
} from "@/hooks/app-user-events.ts";
import type { AppUserProfile } from "@/hooks/use-app-user.ts";
import { hasCompletedOnboarding } from "@/lib/auth/onboarding-completion.ts";

const SELLER_ROLE_NAMES = [
  "vendeur",
  "vendeur_independant",
  "vendeur_reseau",
  "vendeur_master",
] as const;

const THIRD_PARTY_SELLER_ROLE_NAMES = [
  "vendeur_independant",
  "vendeur_reseau",
  "vendeur_master",
] as const;

const SELLER_ACCESS_ROLE_NAMES = [...SELLER_ROLE_NAMES, "owner"] as const;

const MERCHANT_AGENT_CTA_BLOCKING_ROLES = [...SELLER_ACCESS_ROLE_NAMES, "super_admin"] as const;

const MERCHANT_AGENT_CTA_BLOCKING_APPLICATION_STATUSES = [
  "pending",
  "success",
  "approved",
  "accepted",
] as const;

function hasAnyRole(roles: readonly string[], roleNames: readonly string[]) {
  return roleNames.some((roleName) => roles.includes(roleName));
}

function normalizeRoleForUi(role: string): string {
  if (role === "super_admin") return "superadmin";
  return role;
}

const ROLE_PRIORITY = [
  "super_admin",
  "admin_pays",
  "master_independant",
  "master",
  "owner",
  "vendeur_master",
  "comptable_compagnie",
  "controleur",
  "vendeur_reseau",
  "vendeur",
  "vendeur_independant",
  "traveler",
] as const;

function roleNameFromJoin(
  role: { name: string } | { name: string }[] | null | undefined,
): string | null {
  if (!role) return null;
  if (Array.isArray(role)) return role[0]?.name ?? null;
  return role.name ?? null;
}

export type AppUserState = ReturnType<typeof useAppUserState>;

export function useAppUserState() {
  const {
    appUserId,
    isLoading: authLoading,
    isBootstrapping,
    session,
  } = useSupabaseAuth();
  const [profile, setProfile] = useState<AppUserProfile | null>(null);
  const [roles, setRoles] = useState<string[]>([]);
  const [merchantAgentApplicationStatus, setMerchantAgentApplicationStatus] = useState<
    string | null
  >(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isReady, setIsReady] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  const refresh = useCallback(() => {
    setIsLoading(true);
    setIsReady(false);
    setRefreshKey((key) => key + 1);
  }, []);

  useEffect(() => {
    const onRefresh = () => refresh();
    window.addEventListener(APP_USER_REFRESH_EVENT, onRefresh);
    return () => window.removeEventListener(APP_USER_REFRESH_EVENT, onRefresh);
  }, [refresh]);

  useEffect(() => {
    if (!isSupabaseAuth() || !appUserId) {
      setProfile(null);
      setRoles([]);
      setMerchantAgentApplicationStatus(null);
      setIsReady(!session);
      setIsLoading(false);
      return;
    }

    let cancelled = false;
    setIsLoading(true);
    setIsReady(false);
    setError(null);

    void (async () => {
      const { data: userRow, error: userError } = await supabase
        .from("Users")
        .select(
          "id, firstName, lastName, email, username, phone, countryId, profileCompleted, onboardingCompleted",
        )
        .eq("id", appUserId)
        .single();

      if (userError) throw userError;

      const { data: userRoles, error: urError } = await supabase
        .from("UserRoles")
        .select("roleId, Role(name)")
        .eq("userId", appUserId);

      if (urError) throw urError;

      const joinedRoleNames = (userRoles ?? [])
        .map((row) =>
          roleNameFromJoin(row.Role as { name: string } | { name: string }[] | null),
        )
        .filter((name): name is string => Boolean(name));

      const roleIds = Array.from(
        new Set(
          (userRoles ?? [])
            .map((row) => row.roleId as string | null)
            .filter((roleId): roleId is string => Boolean(roleId)),
        ),
      );

      const fallbackRoleNames = joinedRoleNames.length
        ? []
        : roleIds.length
          ? await supabase
              .from("Role")
              .select("id, name")
              .in("id", roleIds)
              .then(({ data, error: rolesError }) => {
                if (rolesError) throw rolesError;
                const namesById = new Map(
                  (data ?? []).map((role) => [role.id as string, role.name as string]),
                );
                return roleIds
                  .map((roleId) => namesById.get(roleId))
                  .filter((name): name is string => Boolean(name));
              })
          : [];
      const roleNames = joinedRoleNames.length ? joinedRoleNames : fallbackRoleNames;

      const { data: merchantAgentApplication } = await supabase
        .from("MerchantAgentApplications")
        .select("status")
        .eq("createdBy", appUserId)
        .order("createdAt", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (!cancelled) {
        setProfile(userRow as AppUserProfile);
        setRoles(roleNames);
        setMerchantAgentApplicationStatus(
          (merchantAgentApplication?.status as string | null | undefined) ?? null,
        );
        setIsReady(true);
      }
    })()
      .catch((err) => {
        if (!cancelled) {
          setError(err instanceof Error ? err : new Error("Profil"));
          setProfile(null);
          setRoles([]);
          setMerchantAgentApplicationStatus(null);
          setIsReady(true);
        }
      })
      .finally(() => {
        if (!cancelled) {
          setIsLoading(false);
          window.dispatchEvent(new Event(APP_USER_REFRESH_DONE_EVENT));
        }
      });

    return () => {
      cancelled = true;
    };
  }, [appUserId, session, refreshKey]);

  const { roles: effectiveRoles, isSandboxActive: isAdminSandbox } = resolveAdminSandboxRoles(
    roles,
    Boolean(session) && isReady,
  );

  const primaryRole =
    ROLE_PRIORITY.find((role) => effectiveRoles.includes(role)) ??
    effectiveRoles[0] ??
    "traveler";

  const primaryRoleUi = normalizeRoleForUi(primaryRole);

  const waitingForProfile =
    !!session && (authLoading || isBootstrapping || !appUserId || !isReady);
  const hasMerchantAgentApplication =
    merchantAgentApplicationStatus !== null &&
    MERCHANT_AGENT_CTA_BLOCKING_APPLICATION_STATUSES.includes(
      merchantAgentApplicationStatus as (typeof MERCHANT_AGENT_CTA_BLOCKING_APPLICATION_STATUSES)[number],
    );
  const hasDbSuperAdmin = roles.includes("super_admin");

  return useMemo(
    () => ({
      profile,
      roles: effectiveRoles,
      hasSellerRole: hasAnyRole(effectiveRoles, SELLER_ROLE_NAMES),
      hasSellerAccess: hasAnyRole(effectiveRoles, SELLER_ACCESS_ROLE_NAMES),
      hasThirdPartySellerRole: hasAnyRole(effectiveRoles, THIRD_PARTY_SELLER_ROLE_NAMES),
      hasMerchantAgentApplication,
      merchantAgentApplicationStatus,
      shouldHideMerchantAgentCta:
        hasAnyRole(effectiveRoles, MERCHANT_AGENT_CTA_BLOCKING_ROLES) || hasMerchantAgentApplication,
      primaryRole,
      primaryRoleUi,
      hasDbSuperAdmin,
      isSuperAdmin: effectiveRoles.includes("super_admin"),
      isAdminSandbox,
      profileCompleted: true,
      onboardingCompleted: hasCompletedOnboarding(profile, appUserId, effectiveRoles),
      isReady,
      isLoading: waitingForProfile || isLoading,
      error,
      refresh,
    }),
    [
      appUserId,
      effectiveRoles,
      error,
      hasDbSuperAdmin,
      hasMerchantAgentApplication,
      isAdminSandbox,
      isLoading,
      isReady,
      merchantAgentApplicationStatus,
      primaryRole,
      primaryRoleUi,
      profile,
      refresh,
      waitingForProfile,
    ],
  );
}
