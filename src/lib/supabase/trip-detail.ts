import { supabase } from "@/lib/supabase";
import type { TripSearchResult } from "@/lib/supabase/trip-search";
import { searchTripsSupabase } from "@/lib/supabase/trip-search";
import { isIssuedTicket } from "@/lib/supabase/ticket-policy";

export type TripDetailResult = TripSearchResult & {
  trajetId: string;
  companyId: string;
  countryId: string;
  bus: {
    busType: string;
    name: string;
    plateNumber?: string;
    amenities?: string[];
  } | null;
};

export type PromoValidationResult = {
  valid: boolean;
  promoId?: string;
  discountAmount?: number;
  code?: string;
  error?: string;
};

export async function getTripDetailSupabase(
  reservationId: string,
): Promise<TripDetailResult | null> {
  const { data: reservation, error } = await supabase
    .from("Reservations")
    .select("id, date, capacity, trajetId")
    .eq("id", reservationId)
    .maybeSingle();

  if (error) throw error;
  if (!reservation) return null;

  const trips = await searchTripsSupabase({ reservationId });
  const base = trips[0];
  if (!base) return null;

  const { data: trajet, error: trajetError } = await supabase
    .from("ProgrammationTrajets")
    .select("id, depart, final, capacity")
    .eq("id", reservation.trajetId as string)
    .maybeSingle();

  if (trajetError) throw trajetError;
  if (!trajet) return null;

  const { data: originGare, error: gareError } = await supabase
    .from("Gares")
    .select("companyId")
    .eq("id", trajet.depart as string)
    .maybeSingle();

  if (gareError) throw gareError;

  const companyId = (originGare?.companyId as string) ?? "";
  let countryId = "";
  if (companyId) {
    const { data: company, error: companyError } = await supabase
      .from("Companies")
      .select("countryId")
      .eq("id", companyId)
      .maybeSingle();
    if (companyError) throw companyError;
    countryId = (company?.countryId as string) ?? "";
  }

  const { data: progBus, error: progBusError } = await supabase
    .from("ProgrammationBus")
    .select("busId")
    .eq("trajetId", trajet.id as string)
    .eq("isActive", true)
    .maybeSingle();

  if (progBusError) throw progBusError;

  let plateNumber: string | undefined;
  if (progBus?.busId) {
    const { data: bus, error: busError } = await supabase
      .from("Bus")
      .select("registrationNumber, model")
      .eq("id", progBus.busId as string)
      .maybeSingle();

    if (busError) throw busError;
    plateNumber = bus?.registrationNumber as string | undefined;
    if (bus?.model && base.bus) {
      base.bus.name = bus.model as string;
    }
  }

  return {
    ...base,
    trajetId: trajet.id as string,
    companyId,
    countryId,
    bus: base.bus
      ? {
          ...base.bus,
          plateNumber,
        }
      : null,
  };
}

export async function getOccupiedSeatsSupabase(
  reservationId: string,
): Promise<string[]> {
  const { data, error } = await supabase.rpc("get_occupied_seats", {
    p_reservation_id: reservationId,
  });

  if (!error && Array.isArray(data)) {
    return data.filter((seat): seat is string => typeof seat === "string");
  }

  // Fallback for local/dev databases where the RPC has not been applied yet.
  const { data: rows, error: rowsError } = await supabase
    .from("ReservationBus")
    .select("seatNumber, isReservation, paymentId")
    .eq("reservationId", reservationId)
    .eq("type", "voyage")
    .not("seatNumber", "is", null);

  if (rowsError) throw rowsError;
  if (!rows?.length) return [];

  const paymentIds = [...new Set(rows.map((r) => r.paymentId as string))];
  const paymentTx = new Map<string, string | null>();

  if (paymentIds.length > 0) {
    const { data: payments, error: paymentError } = await supabase
      .from("Payment")
      .select("id, txID")
      .in("id", paymentIds);

    if (paymentError) throw paymentError;
    for (const payment of payments ?? []) {
      paymentTx.set(payment.id as string, payment.txID as string | null);
    }
  }

  return rows
    .filter((row) => {
      const txID = paymentTx.get(row.paymentId as string);
      return isIssuedTicket(row.isReservation as boolean, txID);
    })
    .map((row) => row.seatNumber as string)
    .filter(Boolean);
}

export async function validatePromoCodeSupabase(
  code: string,
  priceAmount: number,
  trajetId: string,
  companyId: string,
): Promise<PromoValidationResult> {
  const normalized = code.toUpperCase().trim();
  if (!normalized) return { valid: false, error: "Code invalide" };

  const { data: promo, error } = await supabase
    .from("PromoCodes")
    .select(
      "id, code, discountType, discountValue, validFrom, validUntil, maxUsage, usageCount, trajetId, isActive",
    )
    .eq("companyId", companyId)
    .eq("code", normalized)
    .maybeSingle();

  if (error) throw error;
  if (!promo) return { valid: false, error: "Code invalide" };
  if (!promo.isActive) return { valid: false, error: "Code désactivé" };

  const now = new Date().toISOString();
  if (now < (promo.validFrom as string)) {
    return { valid: false, error: "Code pas encore valide" };
  }
  if (now > (promo.validUntil as string)) {
    return { valid: false, error: "Code expiré" };
  }
  if (
    promo.maxUsage != null &&
    (promo.usageCount as number) >= (promo.maxUsage as number)
  ) {
    return { valid: false, error: "Limite d'utilisation atteinte" };
  }
  if (promo.trajetId && promo.trajetId !== trajetId) {
    return { valid: false, error: "Code non applicable à ce trajet" };
  }

  let discountAmount = 0;
  if (promo.discountType === "percentage") {
    discountAmount = Math.round(
      (priceAmount * (promo.discountValue as number)) / 100,
    );
  } else {
    discountAmount = promo.discountValue as number;
  }
  discountAmount = Math.min(discountAmount, priceAmount);

  return {
    valid: true,
    promoId: promo.id as string,
    discountAmount,
    code: promo.code as string,
  };
}

/** Vérification temps réel — aucun siège n'est bloqué tant que le paiement n'est pas confirmé. */
export async function checkTripAvailabilitySupabase(reservationId: string) {
  const trips = await searchTripsSupabase({ reservationId });
  const trip = trips[0];
  if (!trip) {
    return { available: false, seatsAvailable: 0 };
  }
  return {
    available: trip.seatsAvailable > 0,
    seatsAvailable: trip.seatsAvailable,
  };
}
