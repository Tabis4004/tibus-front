import { useCallback, useEffect, useMemo, useRef, useState } from "react";
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
import {
  isProfileComplete,
  shouldBackfillProfileCompleted,
} from "@/lib/auth/profile-completion.ts";
import {
  resolveDashboardRole,
  resolveDashboardRoleUi,
} from "@/lib/auth/role-routing.ts";

const SELLER_ROLE_NAMES = [
  "vendeur",
  "vendeur_gare",
  "chauffeur",
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
  "demarcheur",
  "master_independant",
  "master",
  "owner",
  "vendeur_master",
  "comptable_compagnie",
  "controleur",
  "chauffeur",
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
  const [droits, setDroits] = useState<string[]>([]);
  const [ownedCompanyIds, setOwnedCompanyIds] = useState<string[]>([]);
  const [adminPaysCountryIds, setAdminPaysCountryIds] = useState<string[]>([]);
  const [merchantAgentApplicationStatus, setMerchantAgentApplicationStatus] = useState<
    string | null
  >(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isReady, setIsReady] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const previousAppUserIdRef = useRef<string | null>(null);

  const refresh = useCallback(() => {
    setIsLoading(true);
    setRefreshKey((key) => key + 1);
  }, []);

  useEffect(() => {
    const onRefresh = () => refresh();
    window.addEventListener(APP_USER_REFRESH_EVENT, onRefresh);
    return () => window.removeEventListener(APP_USER_REFRESH_EVENT, onRefresh);
  }, [refresh]);

  useEffect(() => {
    if (!isSupabaseAuth() || !appUserId) {
      previousAppUserIdRef.current = null;
      setProfile(null);
      setRoles([]);
      setDroits([]);
      setOwnedCompanyIds([]);
      setAdminPaysCountryIds([]);
      setMerchantAgentApplicationStatus(null);
      setIsReady(!session);
      setIsLoading(false);
      return;
    }

    const userChanged = previousAppUserIdRef.current !== appUserId;
    previousAppUserIdRef.current = appUserId;

    if (userChanged) {
      setIsReady(false);
      setProfile(null);
      setRoles([]);
      setDroits([]);
      setOwnedCompanyIds([]);
      setAdminPaysCountryIds([]);
      setMerchantAgentApplicationStatus(null);
    }

    let cancelled = false;
    setIsLoading(true);
    setError(null);

    void (async () => {
      const { data: userRow, error: userError } = await supabase
        .from("users")
        .select(
          "id, firstName, lastName, email, username, phone, countryId, profileCompleted, onboardingCompleted",
        )
        .eq("id", appUserId)
        .single();

      if (userError) throw userError;

      const { data: userRoles, error: urError } = await supabase
        .from("UserRoles")
        .select("roleId, companyId, countryId, Role(name, droits)")
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

      // Union des droits (Role.droits) de tous les rôles attribués à
      // l'utilisateur — alimente hasDroit() côté front, en miroir du même
      // mécanisme utilisé côté base par has_company_droit()/has_country_droit().
      const joinedDroits = Array.from(
        new Set(
          (userRoles ?? []).flatMap((row) => {
            const role = row.Role as { droits?: string[] } | { droits?: string[] }[] | null;
            const roleObj = Array.isArray(role) ? role[0] : role;
            return roleObj?.droits ?? [];
          }),
        ),
      );

      let fallbackRoleNames: string[] = [];
      let fallbackDroits: string[] = [];
      if (!joinedRoleNames.length && roleIds.length) {
        const { data: fallbackRoles, error: rolesError } = await supabase
          .from("Role")
          .select("id, name, droits")
          .in("id", roleIds);
        if (rolesError) throw rolesError;
        const byId = new Map(
          (fallbackRoles ?? []).map((role) => [
            role.id as string,
            { name: role.name as string, droits: (role.droits as string[] | null) ?? [] },
          ]),
        );
        fallbackRoleNames = roleIds
          .map((roleId) => byId.get(roleId)?.name)
          .filter((name): name is string => Boolean(name));
        fallbackDroits = Array.from(
          new Set(roleIds.flatMap((roleId) => byId.get(roleId)?.droits ?? [])),
        );
      }
      const roleNames = joinedRoleNames.length ? joinedRoleNames : fallbackRoleNames;
      const droits = joinedRoleNames.length ? joinedDroits : fallbackDroits;

      const ownedCompanyIds = Array.from(
        new Set(
          (userRoles ?? [])
            .filter((row) => {
              const name = roleNameFromJoin(
                row.Role as { name: string } | { name: string }[] | null,
              );
              return name === "owner" && Boolean(row.companyId);
            })
            .map((row) => row.companyId as string),
        ),
      );

      // Pays du/des rôle(s) admin_pays : c'est CE pays qui fait foi pour les
      // droits en base (has_country_role), pas celui du profil — un
      // utilisateur peut être admin pays d'un autre pays que le sien.
      const adminPaysCountryIds = Array.from(
        new Set(
          (userRoles ?? [])
            .filter((row) => {
              const name = roleNameFromJoin(
                row.Role as { name: string } | { name: string }[] | null,
              );
              return name === "admin_pays" && Boolean(row.countryId);
            })
            .map((row) => row.countryId as string),
        ),
      );

      const { data: merchantAgentApplication } = await supabase
        .from("MerchantAgentApplications")
        .select("status")
        .eq("createdBy", appUserId)
        .order("createdAt", { ascending: false })
        .limit(1)
        .maybeSingle();

      let profileRow = userRow as AppUserProfile;

      if (
        profileRow &&
        shouldBackfillProfileCompleted(profileRow, roleNames)
      ) {
        const { error: backfillError } = await supabase
          .from("users")
          .update({ profileCompleted: true })
          .eq("id", appUserId);

        if (!backfillError) {
          profileRow = { ...profileRow, profileCompleted: true };
        }
      }

      if (!cancelled) {
        setProfile(profileRow);
        setRoles(roleNames);
        setDroits(droits);
        setOwnedCompanyIds(ownedCompanyIds);
        setAdminPaysCountryIds(adminPaysCountryIds);
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
          setDroits([]);
          setOwnedCompanyIds([]);
          setAdminPaysCountryIds([]);
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
  }, [appUserId, session?.user?.id, refreshKey]);

  const sessionUserId = session?.user?.id ?? null;
  const isAuthenticatedForProfile = Boolean(sessionUserId) && isReady;

  const { roles: effectiveRoles, isSandboxActive: isAdminSandbox } = useMemo(
    () => resolveAdminSandboxRoles(roles, isAuthenticatedForProfile),
    [roles, isAuthenticatedForProfile],
  );

  const primaryRole =
    ROLE_PRIORITY.find((role) => effectiveRoles.includes(role)) ??
    effectiveRoles[0] ??
    "traveler";

  const primaryRoleUi = normalizeRoleForUi(primaryRole);
  const dashboardRole = resolveDashboardRole(effectiveRoles);
  const dashboardRoleUi = resolveDashboardRoleUi(effectiveRoles);

  const waitingForProfile =
    !!sessionUserId && !isReady && (authLoading || isBootstrapping || !appUserId);
  const hasMerchantAgentApplication =
    merchantAgentApplicationStatus !== null &&
    MERCHANT_AGENT_CTA_BLOCKING_APPLICATION_STATUSES.includes(
      merchantAgentApplicationStatus as (typeof MERCHANT_AGENT_CTA_BLOCKING_APPLICATION_STATUSES)[number],
    );
  const hasDbSuperAdmin = roles.includes("super_admin");
  const isSuperAdminNow = effectiveRoles.includes("super_admin");
  // Union des droits (Role.droits) de tous les rôles réellement attribués en
  // base — le sandbox super_admin (dev only) ne rejoue pas cette union, il
  // s'appuie sur isSuperAdmin qui bypass hasDroit() de toute façon.
  const hasDroit = useCallback(
    (droit: string) => isSuperAdminNow || droits.includes(droit),
    [droits, isSuperAdminNow],
  );

  return useMemo(
    () => ({
      profile,
      roles: effectiveRoles,
      droits,
      hasDroit,
      ownedCompanyIds,
      adminPaysCountryIds,
      hasSellerRole: hasAnyRole(effectiveRoles, SELLER_ROLE_NAMES),
      hasSellerAccess: hasAnyRole(effectiveRoles, SELLER_ACCESS_ROLE_NAMES),
      hasThirdPartySellerRole: hasAnyRole(effectiveRoles, THIRD_PARTY_SELLER_ROLE_NAMES),
      hasMerchantAgentApplication,
      merchantAgentApplicationStatus,
      shouldHideMerchantAgentCta:
        hasAnyRole(effectiveRoles, MERCHANT_AGENT_CTA_BLOCKING_ROLES) || hasMerchantAgentApplication,
      primaryRole,
      primaryRoleUi,
      dashboardRole,
      dashboardRoleUi,
      hasDbSuperAdmin,
      isSuperAdmin: effectiveRoles.includes("super_admin"),
      isAdminSandbox,
      profileCompleted: isProfileComplete(profile, effectiveRoles),
      onboardingCompleted: hasCompletedOnboarding(profile, appUserId, effectiveRoles),
      isReady,
      isLoading: waitingForProfile || (!isReady && isLoading),
      error,
      refresh,
    }),
    [
      adminPaysCountryIds,
      appUserId,
      droits,
      effectiveRoles,
      error,
      hasDbSuperAdmin,
      hasDroit,
      hasMerchantAgentApplication,
      isAdminSandbox,
      isLoading,
      isReady,
      merchantAgentApplicationStatus,
      ownedCompanyIds,
      primaryRole,
      primaryRoleUi,
      dashboardRole,
      dashboardRoleUi,
      profile,
      refresh,
      waitingForProfile,
    ],
  );
}
