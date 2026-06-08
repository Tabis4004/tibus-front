import { supabase } from "@/lib/supabase";
import { throwSupabaseError } from "@/lib/supabase/errors";
import type { SellerCompanyReceiptInfo } from "@/lib/ticket-receipt-print.ts";
import {
  searchTripsSupabase,
  type TripSearchResult,
} from "@/lib/supabase/trip-search";

export type SellerCompany = {
  id: string;
  name: string;
};

export type { SellerCompanyReceiptInfo };

export type SellerProfileSupabase = {
  user: {
    id: string;
    name: string;
    email: string | null;
  };
  company: SellerCompany | null;
  roleNames: string[];
  canSellDirect: boolean;
  canReserveWithGateway: boolean;
  canSellAllCompanies: boolean;
};

export type SellerCounterTrip = TripSearchResult & {
  companyId?: string;
};

export type CounterTravelerInput = {
  passengerName: string;
  passengerPhone?: string;
  seatNumber?: string;
  parcelCount?: number;
  parcelWeight?: number;
  parcelAmount?: number;
};

export type CounterSaleTicket = {
  bookingId: string;
  reference: string;
  verifyToken?: string | null;
  totalPrice: number;
  currency: string;
  passengerName: string;
  passengerPhone?: string;
  seatNumber?: string;
  parcelCount: number;
  parcelWeight: number;
  parcelAmount: number;
};

function roleNameFromJoin(
  role: { name: string } | { name: string }[] | null | undefined,
): string | null {
  if (!role) return null;
  if (Array.isArray(role)) return role[0]?.name ?? null;
  return role.name ?? null;
}

export async function getSellerProfileSupabase(
  appUserId: string,
): Promise<SellerProfileSupabase | null> {
  const { data: user, error: userError } = await supabase
    .from("Users")
    .select("id, firstName, lastName, email")
    .eq("id", appUserId)
    .maybeSingle();

  if (userError) throw userError;
  if (!user) return null;

  const { data: roles, error: rolesError } = await supabase
    .from("UserRoles")
    .select("companyId, Role(name)")
    .eq("userId", appUserId);

  if (rolesError) throw rolesError;

  const sellerRoles = (roles ?? []).filter((row) => {
    const name = roleNameFromJoin(
      row.Role as { name: string } | { name: string }[] | null,
    );
    return [
      "super_admin",
      "vendeur",
      "vendeur_independant",
      "vendeur_reseau",
      "vendeur_master",
      "owner",
    ].includes(name ?? "");
  });

  if (!sellerRoles.length) return null;

  const roleNames = sellerRoles
    .map((row) => roleNameFromJoin(row.Role as { name: string } | { name: string }[] | null))
    .filter((name): name is string => Boolean(name));

  const companySellerRow = sellerRoles.find((row) => {
    const name = roleNameFromJoin(row.Role as { name: string } | { name: string }[] | null);
    return Boolean(row.companyId) && (name === "vendeur" || name === "owner");
  });

  const companyId = (companySellerRow?.companyId ?? sellerRoles.find((row) => row.companyId)?.companyId) as
    | string
    | undefined;

  let company: SellerCompany | null = null;
  if (companyId) {
    const { data: companyRow, error: companyError } = await supabase
      .from("Companies")
      .select("id, name")
      .eq("id", companyId)
      .maybeSingle();

    if (companyError) throw companyError;
    if (companyRow) {
      company = {
        id: companyRow.id as string,
        name: companyRow.name as string,
      };
    }
  }

  const canSellDirect = Boolean(companySellerRow);
  const canReserveWithGateway = roleNames.some((name) =>
    ["vendeur_independant", "vendeur_reseau", "vendeur_master"].includes(name),
  );
  const canSellAllCompanies = roleNames.some((name) =>
    ["super_admin", "vendeur_independant", "vendeur_reseau", "vendeur_master"].includes(name),
  );

  return {
    user: {
      id: user.id as string,
      name: `${user.firstName ?? ""} ${user.lastName ?? ""}`.trim(),
      email: user.email as string | null,
    },
    company,
    roleNames,
    canSellDirect,
    canReserveWithGateway,
    canSellAllCompanies,
  };
}

export async function getSellerCompanyReceiptInfoSupabase(
  companyId: string,
): Promise<SellerCompanyReceiptInfo | null> {
  const { data, error } = await supabase
    .from("Companies")
    .select("name, logo, managerName, voyageColisMsg")
    .eq("id", companyId)
    .maybeSingle();

  if (error) throw error;
  if (!data) return null;

  return {
    name: data.name as string,
    logoUrl: (data.logo as string | null) ?? null,
    boardingMessage: (data.voyageColisMsg as string | null) ?? undefined,
  };
}

export async function listSellerTripsSupabase(
  profile: SellerProfileSupabase,
): Promise<SellerCounterTrip[]> {
  const trips = await searchTripsSupabase(
    profile.company && !profile.canSellAllCompanies
      ? { companyId: profile.company.id }
      : {},
  );

  return trips.filter((trip) => trip.seatsAvailable > 0);
}

export async function sellCounterTicketSupabase(input: {
  reservationId: string;
  traveler: CounterTravelerInput;
}): Promise<CounterSaleTicket> {
  const traveler = input.traveler;
  const { data, error } = await supabase.rpc("seller_counter_sale", {
    p_reservation_id: input.reservationId,
    p_passenger_name: traveler.passengerName.trim(),
    p_passenger_phone: traveler.passengerPhone?.trim() || null,
    p_seat_number: traveler.seatNumber?.trim() || null,
    p_parcel_count: traveler.parcelCount ?? 0,
    p_parcel_weight: traveler.parcelWeight ?? 0,
    p_parcel_amount: traveler.parcelAmount ?? 0,
  });

  if (error) throwSupabaseError(error, "Vente guichet impossible");

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) throw new Error("Ticket non cree");

  return {
    bookingId: row.booking_id as string,
    reference: row.reference as string,
    verifyToken: (row.verify_token as string | null) ?? null,
    totalPrice: row.total_price as number,
    currency: row.currency as string,
    passengerName: traveler.passengerName.trim(),
    passengerPhone: traveler.passengerPhone?.trim() || undefined,
    seatNumber: traveler.seatNumber?.trim() || undefined,
    parcelCount: traveler.parcelCount ?? 0,
    parcelWeight: traveler.parcelWeight ?? 0,
    parcelAmount: traveler.parcelAmount ?? 0,
  };
}
