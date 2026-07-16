import { supabase } from "@/lib/supabase";
import { cityFromGareName, coordinatesFromGoogleMapsLinkAsync } from "@/lib/supabase/gares-map.ts";
import { cityNameFromGareRow } from "@/lib/trip-display.ts";
import {
  resolveOwnerCompanyId,
  setOwnerActiveCompanySupabase,
} from "@/lib/supabase/owner-company";

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
  /// Téléphone de la gare — imprimé sur le reçu colis (courrier agent),
  /// distinct du téléphone de la compagnie (voir colisReceiptLines côté
  /// mobile et ColisReceiptPanel côté web).
  phone: string;
  isActive: boolean;
  cityId: string;
  cityName: string;
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
    .select(
      "id, name, phone, googleMapsLink, cityId, gestionnaireUserId, gestionnaireSharePct, gestionnaireSharePctReservation, Cities(name)",
    )
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
    const cityJoin = station.Cities as { name: string } | { name: string }[] | null;
    const linkedCity =
      Array.isArray(cityJoin) ? cityJoin[0]?.name : cityJoin?.name ?? null;
    const cityName = cityNameFromGareRow(station.name as string, linkedCity);
    return {
      id: station.id as string,
      name: station.name as string,
      address: (station.googleMapsLink as string | null) ?? "",
      phone: (station.phone as string | null) ?? "",
      isActive: true,
      cityId: station.cityId as string,
      cityName,
      location: {
        city: cityName,
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
  cityId: string;
  googleMapsLink?: string;
  phone?: string;
}): Promise<void> {
  const companyId = await resolveOwnerCompanyId(input.appUserId, input.companyId);
  if (!companyId) throw new Error("Compagnie introuvable");
  if (!input.cityId) throw new Error("Ville requise pour la gare");

  const { latitude, longitude } = await coordinatesFromGoogleMapsLinkAsync(input.googleMapsLink, {
    name: input.name,
    city: cityFromGareName(input.name),
  });

  const { error } = await supabase.from("Gares").insert({
    name: input.name.trim(),
    companyId,
    cityId: input.cityId,
    googleMapsLink: input.googleMapsLink?.trim() || null,
    phone: input.phone?.trim() || null,
    latitude,
    longitude,
  });

  if (error) throw error;
}

export async function updateOwnerStationSupabase(input: {
  appUserId: string;
  companyId?: string | null;
  stationId: string;
  name: string;
  cityId: string;
  googleMapsLink?: string;
  phone?: string;
  gestionnaireUserId?: string | null;
  gestionnaireSharePct?: number;
  gestionnaireSharePctReservation?: number;
}): Promise<void> {
  const companyId = await resolveOwnerCompanyId(input.appUserId, input.companyId);
  if (!companyId) throw new Error("Compagnie introuvable");
  if (!input.cityId) throw new Error("Ville requise pour la gare");

  const { latitude, longitude } = await coordinatesFromGoogleMapsLinkAsync(input.googleMapsLink, {
    name: input.name,
    city: cityFromGareName(input.name),
  });

  const { error } = await supabase
    .from("Gares")
    .update({
      name: input.name.trim(),
      cityId: input.cityId,
      googleMapsLink: input.googleMapsLink?.trim() || null,
      phone: input.phone?.trim() || null,
      latitude,
      longitude,
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
    const { assignGareGerantSupabase } = await import("@/lib/supabase/gare-team.ts");
    await setGareManagerRevenueShareSupabase({
      gareId: input.stationId,
      sharePct: input.gestionnaireSharePct ?? 0,
      sharePctReservation: input.gestionnaireSharePctReservation ?? input.gestionnaireSharePct ?? 0,
      gestionnaireUserId: input.gestionnaireUserId ?? null,
    });
    try {
      await assignGareGerantSupabase(input.stationId, input.gestionnaireUserId ?? null);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      if (!/assign_gare_gerant|could not find|PGRST202/i.test(message)) throw err;
    }
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

type TeamRow = {
  user_id: string;
  firstName: string | null;
  lastName: string | null;
  email: string | null;
  role_name: string;
};

function joinedRoleName(
  role: { name: string } | { name: string }[] | null | undefined,
): string | null {
  if (!role) return null;
  if (Array.isArray(role)) return role[0]?.name ?? null;
  return role.name ?? null;
}

function joinedUser(
  user:
    | { id: string; firstName: string | null; lastName: string | null; email: string | null }
    | {
        id: string;
        firstName: string | null;
        lastName: string | null;
        email: string | null;
      }[]
    | null
    | undefined,
) {
  if (!user) return null;
  return Array.isArray(user) ? (user[0] ?? null) : user;
}

function mapTeamRows(rows: TeamRow[]): SupabaseOwnerSeller[] {
  return rows
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

function readSupabaseErrorText(err: unknown): string {
  if (!err || typeof err !== "object") return "";
  const payload = err as {
    message?: string;
    details?: string;
    hint?: string;
    code?: string;
  };
  return [payload.message, payload.details, payload.hint, payload.code]
    .filter((part): part is string => typeof part === "string" && part.length > 0)
    .join(" ");
}

function isRpcSignatureMismatch(err: unknown) {
  const message = readSupabaseErrorText(err);
  return /function|schema cache|could not find|p_company_id|arguments/i.test(message);
}

function isRpcResultTypeMismatch(err: unknown) {
  const message = readSupabaseErrorText(err);
  return (
    /structure of query does not match function result type/i.test(message)
    || message.includes("42804")
  );
}

export async function syncOwnerTeamCompanyContext(companyId: string) {
  try {
    await setOwnerActiveCompanySupabase(companyId);
  } catch {
    // 058 peut ne pas être appliqué : le front garde quand même companyId explicite.
  }
}

async function listOwnerTeamDirectSupabase(companyId: string): Promise<SupabaseOwnerSeller[]> {
  const { data: roleRows, error: roleError } = await supabase
    .from("Role")
    .select("id, name")
    .in("name", [...OWNER_ASSIGNABLE_TEAM_ROLES]);

  if (roleError) throw roleError;

  const roleIds = (roleRows ?? []).map((row) => row.id as string);
  if (!roleIds.length) return [];

  const { data, error } = await supabase
    .from("UserRoles")
    .select("userId, Role(name), Users(id, firstName, lastName, email)")
    .eq("companyId", companyId)
    .in("roleId", roleIds);

  if (error) throw error;

  const rows: TeamRow[] = [];
  for (const entry of data ?? []) {
    const roleName = joinedRoleName(
      entry.Role as { name: string } | { name: string }[] | null,
    );
    const user = joinedUser(
      entry.Users as
        | {
            id: string;
            firstName: string | null;
            lastName: string | null;
            email: string | null;
          }
        | {
            id: string;
            firstName: string | null;
            lastName: string | null;
            email: string | null;
          }[]
        | null,
    );
    if (!roleName || !user) continue;
    rows.push({
      user_id: user.id,
      firstName: user.firstName ?? "",
      lastName: user.lastName ?? "",
      email: user.email,
      role_name: roleName,
    });
  }

  return mapTeamRows(rows);
}

export async function listOwnerSellersSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<SupabaseOwnerSeller[]> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return [];

  await syncOwnerTeamCompanyContext(resolvedCompanyId);

  try {
    return await listOwnerTeamDirectSupabase(resolvedCompanyId);
  } catch (directError) {
    const { data, error } = await supabase.rpc("list_owner_team_members", {
      p_company_id: resolvedCompanyId,
    });
    if (!error) {
      return mapTeamRows((data ?? []) as TeamRow[]);
    }
    if (isRpcResultTypeMismatch(error) || isRpcSignatureMismatch(error)) {
      throw directError;
    }
    throw error;
  }
}

export async function findAssignableCompanyUserByEmailSupabase(
  email: string,
  companyId?: string | null,
): Promise<SupabaseAssignableUser | null> {
  if (companyId) {
    await syncOwnerTeamCompanyContext(companyId);
  }

  const normalizedEmail = email.trim().toLowerCase();
  const { data, error } = await supabase.rpc(
    "find_assignable_company_user_by_email",
    { p_email: normalizedEmail },
  );

  if (!error) {
    const row = Array.isArray(data) ? data[0] : null;
    if (!row) return null;
    return {
      id: row.id as string,
      name: fullName(row),
      email: (row.email as string | null) ?? null,
    };
  }

  if (!isRpcResultTypeMismatch(error)) throw error;

  const { data: userRow, error: directError } = await supabase
    .from("Users")
    .select("id, firstName, lastName, email")
    .ilike("email", normalizedEmail)
    .maybeSingle();

  if (directError) {
    throw new Error(
      "Migration SQL 081_owner_team_rpc_definitive.sql requise sur Supabase pour rechercher un membre par email.",
      { cause: directError },
    );
  }
  if (!userRow) return null;

  return {
    id: userRow.id,
    name: fullName(userRow),
    email: userRow.email ?? null,
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
  const email = input.email.trim().toLowerCase();
  const roleName = input.roleName ?? "vendeur";
  const companyId = input.companyId;
  if (!companyId) throw new Error("Compagnie introuvable");

  await syncOwnerTeamCompanyContext(companyId);

  const withCompany = await supabase.rpc("assign_company_user_role_by_email", {
    p_email: email,
    p_role_name: roleName,
    p_company_id: companyId ?? null,
  });

  let result = withCompany;
  if (withCompany.error && isRpcSignatureMismatch(withCompany.error)) {
    result = await supabase.rpc("assign_company_user_role_by_email", {
      p_email: email,
      p_role_name: roleName,
    });
  }

  if (result.error && isRpcResultTypeMismatch(result.error)) {
    const { data: userRow, error: lookupError } = await supabase
      .from("Users")
      .select("id, firstName, lastName, email")
      .ilike("email", email)
      .maybeSingle();
    if (lookupError) {
      throw new Error(
        "Migration SQL 081_owner_team_rpc_definitive.sql requise sur Supabase pour attribuer un membre.",
        { cause: lookupError },
      );
    }
    if (!userRow) throw new Error("Aucun utilisateur inscrit avec cet email");

    const roleRow = await supabase
      .from("Role")
      .select("id")
      .eq("name", roleName)
      .eq("scope", "company")
      .maybeSingle();
    if (roleRow.error) throw roleRow.error;
    if (!roleRow.data?.id) throw new Error(`Rôle introuvable : ${roleName}`);

    const { error: insertError } = await supabase.from("UserRoles").insert({
      roleId: roleRow.data.id,
      userId: userRow.id,
      companyId,
      countryId: null,
    });
    if (insertError && !/duplicate|unique|already exists/i.test(insertError.message)) {
      throw insertError;
    }

    return {
      id: userRow.id,
      name: fullName(userRow),
      email: userRow.email ?? null,
    };
  }

  if (result.error) throw result.error;

  const row = Array.isArray(result.data) ? result.data[0] : null;
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
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) throw new Error("Compagnie introuvable");

  await syncOwnerTeamCompanyContext(resolvedCompanyId);

  if (roleName) {
    const withCompany = await supabase.rpc("remove_company_user_role", {
      p_user_id: userId,
      p_role_name: roleName,
      p_company_id: resolvedCompanyId,
    });

    if (withCompany.error && isRpcSignatureMismatch(withCompany.error)) {
      const legacy = await supabase.rpc("remove_company_user_role", {
        p_user_id: userId,
        p_role_name: roleName,
      });
      if (legacy.error) throw legacy.error;
    } else if (withCompany.error) {
      throw withCompany.error;
    }
    return;
  }

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
