import { supabase } from "@/lib/supabase";

export type OwnerCompany = {
  id: string;
  name: string;
  logo: string | null;
  managerName: string | null;
  commissionRate: number;
  isActive: boolean;
  currency: string | null;
};

export type OwnerCompanyDetails = OwnerCompany & {
  voyageColisMsg: string | null;
  arretReservation: boolean;
};

export type OwnerKPIs = {
  totalBuses: number;
  upcomingTrips: number;
  totalSellers: number;
  totalBookings: number;
};

function roleNameFromJoin(
  role: { name: string } | { name: string }[] | null | undefined,
): string | null {
  if (!role) return null;
  if (Array.isArray(role)) return role[0]?.name ?? null;
  return role.name ?? null;
}

export const COMPANY_STAFF_ROLE_NAMES = [
  "owner",
  "comptable_compagnie",
  "controleur",
  "vendeur",
  "chauffeur",
] as const;

export type CompanyStaffRole = (typeof COMPANY_STAFF_ROLE_NAMES)[number];

export async function resolveCompanyStaffCompanyId(
  appUserId: string,
): Promise<string | null> {
  const { data, error } = await supabase
    .from("UserRoles")
    .select("companyId, Role(name)")
    .eq("userId", appUserId);

  if (error) throw error;

  const staffRow = (data ?? []).find((row) => {
    const name = roleNameFromJoin(row.Role as { name: string } | { name: string }[]);
    return Boolean(row.companyId) && COMPANY_STAFF_ROLE_NAMES.includes(name as CompanyStaffRole);
  });

  return (staffRow?.companyId as string) ?? null;
}

export type OwnerCompanyOption = {
  id: string;
  name: string;
  countryId: string | null;
  countryName: string | null;
  currency: string | null;
  logo: string | null;
};

export function ownerCompanyStorageKey(userId: string) {
  return `tibus:owner-company:${userId}`;
}

function joinedOne<T>(value: T | T[] | null | undefined): T | null {
  if (!value) return null;
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

function sortOwnerCompanyOptions(companies: OwnerCompanyOption[]) {
  return [...companies].sort((a, b) => {
    const countryCompare = (a.countryName ?? "").localeCompare(b.countryName ?? "");
    if (countryCompare !== 0) return countryCompare;
    return a.name.localeCompare(b.name);
  });
}

function ownerCompanyOptionFromCompanyRow(row: {
  id: string;
  name: string;
  logo?: string | null;
  countryId?: string | null;
  Countries?:
    | { name: string; currency: string | null }
    | { name: string; currency: string | null }[]
    | null;
}): OwnerCompanyOption {
  const country = joinedOne(row.Countries ?? null);
  return {
    id: row.id,
    name: row.name,
    countryId: (row.countryId as string | null) ?? null,
    countryName: country?.name ?? null,
    currency: country?.currency ?? null,
    logo: (row.logo as string | null) ?? null,
  };
}

export async function isAppUserSuperAdminSupabase(
  appUserId: string,
): Promise<boolean> {
  const { data, error } = await supabase
    .from("UserRoles")
    .select("Role(name)")
    .eq("userId", appUserId);

  if (error) throw error;

  return (data ?? []).some((row) => {
    const name = roleNameFromJoin(row.Role as { name: string } | { name: string }[]);
    return name === "super_admin";
  });
}

async function listOwnedCompaniesOnlySupabase(
  appUserId: string,
): Promise<OwnerCompanyOption[]> {
  const { data, error } = await supabase
    .from("UserRoles")
    .select(
      "companyId, Role(name), Companies(id, name, logo, countryId, Countries(name, currency))",
    )
    .eq("userId", appUserId);

  if (error) throw error;

  const companies = new Map<string, OwnerCompanyOption>();
  for (const row of data ?? []) {
    if (roleNameFromJoin(row.Role as { name: string } | { name: string }[]) !== "owner") {
      continue;
    }
    const companyId = row.companyId as string | null;
    if (!companyId) continue;

    const joined = joinedOne(
      row.Companies as
        | {
            name?: string;
            logo?: string | null;
            countryId?: string | null;
            Countries?:
              | { name: string; currency: string | null }
              | { name: string; currency: string | null }[]
              | null;
          }
        | {
            name?: string;
            logo?: string | null;
            countryId?: string | null;
            Countries?:
              | { name: string; currency: string | null }
              | { name: string; currency: string | null }[]
              | null;
          }[]
        | null,
    );
    if (!joined?.name) continue;

    companies.set(companyId, ownerCompanyOptionFromCompanyRow({
      id: companyId,
      name: joined.name,
      logo: joined.logo,
      countryId: joined.countryId,
      Countries: joined.Countries,
    }));
  }

  return sortOwnerCompanyOptions([...companies.values()]);
}

export async function listAllCompaniesAsOwnerOptionsSupabase(): Promise<OwnerCompanyOption[]> {
  const { data, error } = await supabase
    .from("Companies")
    .select("id, name, logo, countryId, Countries(name, currency)")
    .order("name", { ascending: true });

  if (error) throw error;

  return sortOwnerCompanyOptions(
    (data ?? []).map((row) =>
      ownerCompanyOptionFromCompanyRow({
        id: row.id as string,
        name: row.name as string,
        logo: row.logo as string | null,
        countryId: row.countryId as string | null,
        Countries: row.Countries as
          | { name: string; currency: string | null }
          | { name: string; currency: string | null }[]
          | null,
      }),
    ),
  );
}

export async function listOwnerCompaniesSupabase(
  appUserId: string,
  options?: { isSuperAdmin?: boolean },
): Promise<OwnerCompanyOption[]> {
  const isSuperAdmin =
    options?.isSuperAdmin ?? (await isAppUserSuperAdminSupabase(appUserId));

  if (isSuperAdmin) {
    return listAllCompaniesAsOwnerOptionsSupabase();
  }

  return listOwnedCompaniesOnlySupabase(appUserId);
}

async function readStoredActiveOwnerCompanyId(
  appUserId: string,
): Promise<string | null> {
  const { data, error } = await supabase
    .from("Users")
    .select("activeOwnerCompanyId")
    .eq("id", appUserId)
    .maybeSingle();

  if (error) {
    if (error.code === "42703") return null;
    throw error;
  }

  return (data?.activeOwnerCompanyId as string | null) ?? null;
}

export async function resolveOwnerCompanyId(
  appUserId: string,
  preferredCompanyId?: string | null,
  options?: { isSuperAdmin?: boolean },
): Promise<string | null> {
  const isSuperAdmin =
    options?.isSuperAdmin ?? (await isAppUserSuperAdminSupabase(appUserId));
  const companies = await listOwnerCompaniesSupabase(appUserId, { isSuperAdmin });

  const storedActive = await readStoredActiveOwnerCompanyId(appUserId);
  const localStored =
    typeof localStorage !== "undefined"
      ? localStorage.getItem(ownerCompanyStorageKey(appUserId))
      : null;

  const candidates = [preferredCompanyId, storedActive, localStored].filter(
    (id): id is string => Boolean(id),
  );

  for (const candidateId of candidates) {
    if (companies.some((company) => company.id === candidateId)) {
      return candidateId;
    }
  }

  if (isSuperAdmin || candidates.length > 0) {
    for (const candidateId of candidates) {
      const { data, error } = await supabase
        .from("Companies")
        .select("id")
        .eq("id", candidateId)
        .maybeSingle();
      if (!error && data) return candidateId;
    }
  }

  return companies[0]?.id ?? null;
}

export async function enterSuperAdminOwnerCompanyContext(
  appUserId: string,
  companyId: string,
): Promise<void> {
  const { data, error } = await supabase
    .from("Companies")
    .select("id")
    .eq("id", companyId)
    .maybeSingle();

  if (error) throw error;
  if (!data) throw new Error("Compagnie introuvable");

  localStorage.setItem(ownerCompanyStorageKey(appUserId), companyId);

  try {
    await setOwnerActiveCompanySupabase(companyId);
  } catch {
    // Keep local selection when RPC is not deployed yet
  }
}

export async function createOwnerCompanySupabase(input: {
  name: string;
  countryId: string;
  managerName?: string | null;
  logo?: string | null;
  voyageColisMsg?: string | null;
  arretReservation?: boolean;
}): Promise<string> {
  const { data, error } = await supabase.rpc("create_owner_company", {
    p_name: input.name.trim(),
    p_country_id: input.countryId,
    p_manager_name: input.managerName?.trim() || null,
    p_logo: input.logo?.trim() || null,
    p_voyage_colis_msg: input.voyageColisMsg?.trim() || null,
    p_arret_reservation: input.arretReservation ?? true,
  });

  if (error) throw error;
  if (!data) throw new Error("Création de compagnie impossible");

  return data as string;
}

export async function setOwnerActiveCompanySupabase(
  companyId: string,
): Promise<void> {
  const { error } = await supabase.rpc("set_owner_active_company", {
    p_company_id: companyId,
  });
  if (error) throw error;
}

export async function getOwnerCompanyDetailsSupabase(
  appUserId: string,
  preferredCompanyId?: string | null,
): Promise<OwnerCompanyDetails | null> {
  const companyId = await resolveOwnerCompanyId(appUserId, preferredCompanyId);
  if (!companyId) return null;

  const { data, error } = await supabase
    .from("Companies")
    .select(
      "id, name, logo, managerName, commissionRate, isActive, countryId, voyageColisMsg, arretReservation",
    )
    .eq("id", companyId)
    .maybeSingle();

  if (error) throw error;
  if (!data) return null;

  const { data: country, error: countryError } = await supabase
    .from("Countries")
    .select("currency")
    .eq("id", data.countryId as string)
    .maybeSingle();

  if (countryError) throw countryError;

  return {
    id: data.id as string,
    name: data.name as string,
    logo: (data.logo as string | null) ?? null,
    managerName: (data.managerName as string | null) ?? null,
    commissionRate: data.commissionRate as number,
    isActive: data.isActive as boolean,
    currency: (country?.currency as string | null) ?? "XOF",
    voyageColisMsg: (data.voyageColisMsg as string | null) ?? null,
    arretReservation: Boolean(data.arretReservation),
  };
}

export async function updateOwnerCompanySupabase(
  companyId: string,
  patch: {
    name?: string;
    logo?: string | null;
    managerName?: string | null;
    voyageColisMsg?: string | null;
    arretReservation?: boolean;
  },
): Promise<void> {
  const { error } = await supabase.from("Companies").update(patch).eq("id", companyId);
  if (error) throw error;
}

export async function getCompanyForAppUserSupabase(
  appUserId: string,
): Promise<OwnerCompany | null> {
  const companyId = await resolveCompanyStaffCompanyId(appUserId);
  if (!companyId) return null;

  const { data, error } = await supabase
    .from("Companies")
    .select("id, name, logo, managerName, commissionRate, isActive, countryId")
    .eq("id", companyId)
    .maybeSingle();

  if (error) throw error;
  if (!data) return null;

  const { data: country, error: countryError } = await supabase
    .from("Countries")
    .select("currency")
    .eq("id", data.countryId as string)
    .maybeSingle();

  if (countryError) throw countryError;

  return {
    id: data.id as string,
    name: data.name as string,
    logo: (data.logo as string | null) ?? null,
    managerName: (data.managerName as string | null) ?? null,
    commissionRate: data.commissionRate as number,
    isActive: data.isActive as boolean,
    currency: (country?.currency as string | null) ?? "XOF",
  };
}

export async function getMyCompanySupabase(
  appUserId: string,
  preferredCompanyId?: string | null,
): Promise<OwnerCompany | null> {
  const companyId = await resolveOwnerCompanyId(appUserId, preferredCompanyId);
  if (!companyId) return null;

  const { data, error } = await supabase
    .from("Companies")
    .select("id, name, logo, managerName, commissionRate, isActive, countryId")
    .eq("id", companyId)
    .maybeSingle();

  if (error) throw error;
  if (!data) return null;

  const { data: country, error: countryError } = await supabase
    .from("Countries")
    .select("currency")
    .eq("id", data.countryId as string)
    .maybeSingle();

  if (countryError) throw countryError;

  return {
    id: data.id as string,
    name: data.name as string,
    logo: (data.logo as string | null) ?? null,
    managerName: (data.managerName as string | null) ?? null,
    commissionRate: data.commissionRate as number,
    isActive: data.isActive as boolean,
    currency: (country?.currency as string | null) ?? "XOF",
  };
}

export async function getOwnerKPIsSupabase(
  appUserId: string,
  preferredCompanyId?: string | null,
): Promise<OwnerKPIs | null> {
  const companyId = await resolveOwnerCompanyId(appUserId, preferredCompanyId);
  if (!companyId) return null;

  const now = new Date().toISOString();

  const [
    { count: busCount, error: busError },
    { data: gares, error: garesError },
    { data: sellerRoles, error: sellerError },
  ] = await Promise.all([
    supabase
      .from("Bus")
      .select("id", { count: "exact", head: true })
      .eq("companyId", companyId)
      .eq("isActive", true),
    supabase.from("Gares").select("id").eq("companyId", companyId),
    supabase
      .from("UserRoles")
      .select("Role(name)")
      .eq("companyId", companyId),
  ]);

  if (busError) throw busError;
  if (garesError) throw garesError;
  if (sellerError) throw sellerError;

  const totalSellers = (sellerRoles ?? []).filter((row) => {
    const name = roleNameFromJoin(
      row.Role as { name: string } | { name: string }[],
    );
    return name === "vendeur" || name === "chauffeur" || name === "controleur" || name === "comptable_compagnie";
  }).length;

  const gareIds = (gares ?? []).map((g) => g.id as string);
  if (!gareIds.length) {
    return {
      totalBuses: busCount ?? 0,
      upcomingTrips: 0,
      totalSellers: 0,
      totalBookings: 0,
    };
  }

  const { data: trajets, error: trajetsError } = await supabase
    .from("ProgrammationTrajets")
    .select("id")
    .in("depart", gareIds);

  if (trajetsError) throw trajetsError;

  const trajetIds = (trajets ?? []).map((t) => t.id as string);

  let upcomingTrips = 0;
  let reservationIds: string[] = [];

  if (trajetIds.length > 0) {
    const { data: reservations, error: resError } = await supabase
      .from("Reservations")
      .select("id, date")
      .in("trajetId", trajetIds);

    if (resError) throw resError;

    reservationIds = (reservations ?? []).map((r) => r.id as string);
    upcomingTrips = (reservations ?? []).filter(
      (r) => (r.date as string) > now,
    ).length;
  }

  let totalBookings = 0;
  if (reservationIds.length > 0) {
    const { data: bookings, error: bookingsError } = await supabase
      .from("ReservationBus")
      .select("isReservation, paymentId")
      .in("reservationId", reservationIds)
      .eq("type", "voyage");

    if (bookingsError) throw bookingsError;

    const paymentIds = [
      ...new Set((bookings ?? []).map((b) => b.paymentId as string)),
    ];

    const paymentTx = new Map<string, string | null>();
    if (paymentIds.length > 0) {
      const { data: payments, error: payError } = await supabase
        .from("Payment")
        .select("id, txID")
        .in("id", paymentIds);
      if (payError) throw payError;
      for (const p of payments ?? []) {
        paymentTx.set(p.id as string, p.txID as string | null);
      }
    }

    totalBookings = (bookings ?? []).filter((b) => {
      const tx = paymentTx.get(b.paymentId as string);
      return !b.isReservation || Boolean(tx);
    }).length;
  }

  return {
    totalBuses: busCount ?? 0,
    upcomingTrips,
    totalSellers,
    totalBookings,
  };
}
