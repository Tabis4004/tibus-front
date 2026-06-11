import { supabase } from "@/lib/supabase";
import { resolveOwnerCompanyId } from "@/lib/supabase/owner-company";

export type SupabaseOwnerBus = {
  id: string;
  name: string;
  plateNumber: string;
  capacity: number;
  busType: string;
  amenities: string[];
  isActive: boolean;
};

export type SupabaseOwnerStation = {
  id: string;
  name: string;
  address: string;
  isActive: boolean;
  location: { city: string; country: string } | null;
  gestionnaireUserId: string | null;
  gestionnaireSharePct: number;
  gestionnaireSharePctReservation: number;
  gestionnaireName: string | null;
};

import {
  OWNER_ASSIGNABLE_TEAM_ROLES,
  isOwnerAssignableTeamRole,
  type OwnerAssignableTeamRole,
} from "@/lib/owner-team-roles.ts";

export type OwnerTeamRoleName = OwnerAssignableTeamRole;

export type SupabaseOwnerSeller = {
  id: string;
  name: string;
  email: string | null;
  roleName: OwnerTeamRoleName;
};

export type SupabaseOwnerTeamMember = {
  id: string;
  name: string;
  email: string | null;
  roles: OwnerTeamRoleName[];
};

export type SupabaseAssignableUser = {
  id: string;
  name: string;
  email: string | null;
};

function cityFromGare(gareName: string): string {
  const parts = gareName.split("—");
  if (parts.length > 1) return parts[parts.length - 1].trim();
  return gareName.replace(/^Gare\s+/i, "").trim();
}

function fullName(user: {
  firstName?: string | null;
  lastName?: string | null;
  email?: string | null;
}) {
  const name = [user.firstName, user.lastName].filter(Boolean).join(" ").trim();
  return name || user.email || "Utilisateur";
}

export async function listOwnerFleetBusesSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<SupabaseOwnerBus[]> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return [];

  const { data, error } = await supabase
    .from("Bus")
    .select("id, model, registrationNumber, capacity, isActive")
    .eq("companyId", resolvedCompanyId)
    .order("registrationNumber");

  if (error) throw error;

  return (data ?? []).map((bus) => ({
    id: bus.id as string,
    name: (bus.model as string | null) || "Bus",
    plateNumber: bus.registrationNumber as string,
    capacity: bus.capacity as number,
    busType: "standard",
    amenities: [],
    isActive: bus.isActive as boolean,
  }));
}

export async function createOwnerBusSupabase(input: {
  appUserId: string;
  companyId?: string | null;
  name: string;
  plateNumber: string;
  capacity: number;
}): Promise<void> {
  const companyId = await resolveOwnerCompanyId(input.appUserId, input.companyId);
  if (!companyId) throw new Error("Compagnie introuvable");

  const { error } = await supabase.from("Bus").insert({
    registrationNumber: input.plateNumber.trim(),
    model: input.name.trim(),
    capacity: input.capacity,
    companyId,
    isActive: true,
  });

  if (error) throw error;
}

export async function updateOwnerBusSupabase(input: {
  appUserId: string;
  companyId?: string | null;
  busId: string;
  name: string;
  plateNumber: string;
  capacity: number;
  isActive: boolean;
}): Promise<void> {
  const companyId = await resolveOwnerCompanyId(input.appUserId, input.companyId);
  if (!companyId) throw new Error("Compagnie introuvable");

  const { error } = await supabase
    .from("Bus")
    .update({
      registrationNumber: input.plateNumber.trim(),
      model: input.name.trim(),
      capacity: input.capacity,
      isActive: input.isActive,
    })
    .eq("id", input.busId)
    .eq("companyId", companyId);

  if (error) throw error;
}

export async function deleteOwnerBusSupabase(
  appUserId: string,
  busId: string,
  companyId?: string | null,
): Promise<void> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) throw new Error("Compagnie introuvable");

  const { error } = await supabase
    .from("Bus")
    .delete()
    .eq("id", busId)
    .eq("companyId", resolvedCompanyId);

  if (error) throw error;
}

export async function listOwnerStationsSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<SupabaseOwnerStation[]> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return [];

  const { data, error } = await supabase
    .from("Gares")
    .select("id, name, googleMapsLink, gestionnaireUserId, gestionnaireSharePct, gestionnaireSharePctReservation")
    .eq("companyId", resolvedCompanyId)
    .order("name");

  if (error) throw error;

  const managerIds = [
    ...new Set(
      (data ?? [])
        .map((station) => station.gestionnaireUserId as string | null)
        .filter((id): id is string => Boolean(id)),
    ),
  ];

  const managerNameById = new Map<string, string>();
  if (managerIds.length) {
    const { data: managers } = await supabase
      .from("Users")
      .select("id, firstName, lastName, email")
      .in("id", managerIds);
    for (const manager of managers ?? []) {
      managerNameById.set(manager.id as string, fullName(manager));
    }
  }

  return (data ?? []).map((station) => {
    const gestionnaireUserId = (station.gestionnaireUserId as string | null) ?? null;
    return {
      id: station.id as string,
      name: station.name as string,
      address: (station.googleMapsLink as string | null) ?? "",
      isActive: true,
      location: {
        city: cityFromGare(station.name as string),
        country: "",
      },
      gestionnaireUserId,
      gestionnaireSharePct: Number(station.gestionnaireSharePct ?? 0),
      gestionnaireSharePctReservation: Number(station.gestionnaireSharePctReservation ?? station.gestionnaireSharePct ?? 0),
      gestionnaireName: gestionnaireUserId
        ? (managerNameById.get(gestionnaireUserId) ?? null)
        : null,
    };
  });
}

export async function createOwnerStationSupabase(input: {
  appUserId: string;
  companyId?: string | null;
  name: string;
  googleMapsLink?: string;
}): Promise<void> {
  const companyId = await resolveOwnerCompanyId(input.appUserId, input.companyId);
  if (!companyId) throw new Error("Compagnie introuvable");

  const { error } = await supabase.from("Gares").insert({
    name: input.name.trim(),
    companyId,
    googleMapsLink: input.googleMapsLink?.trim() || null,
  });

  if (error) throw error;
}

export async function updateOwnerStationSupabase(input: {
  appUserId: string;
  companyId?: string | null;
  stationId: string;
  name: string;
  googleMapsLink?: string;
  gestionnaireUserId?: string | null;
  gestionnaireSharePct?: number;
  gestionnaireSharePctReservation?: number;
}): Promise<void> {
  const companyId = await resolveOwnerCompanyId(input.appUserId, input.companyId);
  if (!companyId) throw new Error("Compagnie introuvable");

  const { error } = await supabase
    .from("Gares")
    .update({
      name: input.name.trim(),
      googleMapsLink: input.googleMapsLink?.trim() || null,
    })
    .eq("id", input.stationId)
    .eq("companyId", companyId);

  if (error) throw error;

  if (
    input.gestionnaireSharePct !== undefined ||
    input.gestionnaireSharePctReservation !== undefined ||
    input.gestionnaireUserId !== undefined
  ) {
    const { setGareManagerRevenueShareSupabase } = await import(
      "@/lib/supabase/gare-manager-revenue.ts"
    );
    await setGareManagerRevenueShareSupabase({
      gareId: input.stationId,
      sharePct: input.gestionnaireSharePct ?? 0,
      sharePctReservation: input.gestionnaireSharePctReservation ?? input.gestionnaireSharePct ?? 0,
      gestionnaireUserId: input.gestionnaireUserId ?? null,
    });
  }
}

export async function deleteOwnerStationSupabase(
  appUserId: string,
  stationId: string,
  companyId?: string | null,
): Promise<void> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) throw new Error("Compagnie introuvable");

  const { error } = await supabase
    .from("Gares")
    .delete()
    .eq("id", stationId)
    .eq("companyId", resolvedCompanyId);

  if (error) throw error;
}

export async function listOwnerSellersSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<SupabaseOwnerSeller[]> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return [];

  const { data, error } = await supabase.rpc("list_owner_team_members", {
    p_company_id: resolvedCompanyId,
  });

  if (error) throw error;

  type TeamRow = {
    user_id: string;
    firstName: string | null;
    lastName: string | null;
    email: string | null;
    role_name: string;
  };

  return ((data ?? []) as TeamRow[])
    .map((row) => {
      const roleName = row.role_name;
      if (!isOwnerAssignableTeamRole(roleName)) return null;

      const user = {
        firstName: row.firstName as string | null,
        lastName: row.lastName as string | null,
        email: row.email as string | null,
      };

      return {
        id: row.user_id as string,
        name: fullName(user),
        email: user.email ?? null,
        roleName: roleName as OwnerTeamRoleName,
      };
    })
    .filter((seller): seller is SupabaseOwnerSeller => Boolean(seller))
    .sort((a, b) => a.name.localeCompare(b.name));
}

export async function findAssignableCompanyUserByEmailSupabase(
  email: string,
): Promise<SupabaseAssignableUser | null> {
  const { data, error } = await supabase.rpc(
    "find_assignable_company_user_by_email",
    { p_email: email.trim().toLowerCase() },
  );

  if (error) throw error;

  const row = Array.isArray(data) ? data[0] : null;
  if (!row) return null;

  return {
    id: row.id as string,
    name: fullName(row),
    email: (row.email as string | null) ?? null,
  };
}

export async function listOwnerTeamSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<SupabaseOwnerTeamMember[]> {
  const sellers = await listOwnerSellersSupabase(appUserId, companyId);
  const byUser = new Map<string, SupabaseOwnerTeamMember>();

  for (const row of sellers) {
    const existing = byUser.get(row.id);
    if (existing) {
      if (!existing.roles.includes(row.roleName)) {
        existing.roles.push(row.roleName);
      }
      continue;
    }
    byUser.set(row.id, {
      id: row.id,
      name: row.name,
      email: row.email,
      roles: [row.roleName],
    });
  }

  return [...byUser.values()].sort((a, b) => a.name.localeCompare(b.name));
}

export async function assignCompanySellerByEmailSupabase(input: {
  email: string;
  roleName?: OwnerTeamRoleName;
  companyId?: string | null;
}): Promise<SupabaseAssignableUser> {
  const { data, error } = await supabase.rpc("assign_company_user_role_by_email", {
    p_email: input.email.trim().toLowerCase(),
    p_role_name: input.roleName ?? "vendeur",
    p_company_id: input.companyId ?? null,
  });

  if (error) throw error;

  const row = Array.isArray(data) ? data[0] : null;
  if (!row) throw new Error("Utilisateur introuvable");

  return {
    id: row.id as string,
    name: fullName(row),
    email: (row.email as string | null) ?? null,
  };
}

export async function removeCompanySellerSupabase(
  appUserId: string,
  userId: string,
  roleName?: OwnerTeamRoleName,
  companyId?: string | null,
): Promise<void> {
  if (roleName) {
    const { error } = await supabase.rpc("remove_company_user_role", {
      p_user_id: userId,
      p_role_name: roleName,
      p_company_id: companyId ?? null,
    });
    if (error) throw error;
    return;
  }

  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) throw new Error("Compagnie introuvable");

  const { data: roles, error: roleError } = await supabase
    .from("Role")
    .select("id")
    .in("name", [...OWNER_ASSIGNABLE_TEAM_ROLES]);

  if (roleError) throw roleError;

  const roleIds = (roles ?? []).map((role) => role.id as string);
  if (!roleIds.length) return;

  const { error } = await supabase
    .from("UserRoles")
    .delete()
    .eq("companyId", resolvedCompanyId)
    .eq("userId", userId)
    .in("roleId", roleIds);

  if (error) throw error;
}
