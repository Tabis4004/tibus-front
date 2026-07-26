import { supabase } from "@/lib/supabase";
import { getTripDetailSupabase } from "@/lib/supabase/trip-detail";
import { searchTripsSupabase } from "@/lib/supabase/trip-search";
import { isIssuedTicket } from "@/lib/supabase/ticket-policy";

export type IssuePaidTicketParams = {
  reservationId: string;
  appUserId: string;
  passengerName: string;
  passengerPhone?: string;
  promoId?: string;
  discountAmount?: number;
  seatNumber?: string;
  paymentTxId: string;
};

export type IssuePaidTicketResult = {
  bookingId: string;
  reference: string;
  verifyToken?: string | null;
  totalPrice: number;
  currency: string;
};

function generateTicketRef(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let ref = "TB-";
  for (let i = 0; i < 8; i++) {
    ref += chars[Math.floor(Math.random() * chars.length)];
  }
  return ref;
}

export type TravelerBookingStatus =
  | "pending_payment"
  | "confirmed"
  | "cancelled"
  | "collected";

export type TravelerBooking = {
  _id: string;
  bookingReference: string;
  verifyToken?: string | null;
  passengerName: string;
  passengerPhone?: string;
  seatNumber?: string;
  totalPrice: number;
  currency: string;
  status: TravelerBookingStatus;
  paymentStatus: "pending" | "paid";
  createdAt: string;
  reservationId: string;
  trip: {
    departureTime: string;
    arrivalTime: string;
    seatsAvailable?: number;
    totalSeats?: number;
  } | null;
  originLoc: { city: string; country?: string } | null;
  destLoc: { city: string; country?: string } | null;
  company: { name: string } | null;
  origin: { name: string; address?: string } | null;
  destination: { name: string; address?: string } | null;
  bus: {
    name: string;
    plateNumber?: string;
    busType?: string;
    capacity?: number;
  } | null;
};

type ReservationBusRow = {
  id: string;
  reservationId: string;
  price: number;
  isReservation: boolean;
  createdAt: string;
  paymentId: string;
  passengerName: string | null;
  seatNumber: string | null;
  verifyToken?: string | null;
};

type PaymentRow = {
  id: string;
  reference: string;
  phone: string;
  amount: number;
  txID: string | null;
};

function deriveStatus(
  isReservation: boolean,
  txID: string | null | undefined,
  departureTime: string,
): TravelerBookingStatus {
  const departed = new Date(departureTime) < new Date();
  if (isReservation && !txID) return "pending_payment";
  if (!isReservation || txID) {
    return departed ? "collected" : "confirmed";
  }
  return "pending_payment";
}

function derivePaymentStatus(
  isReservation: boolean,
  txID: string | null | undefined,
): "pending" | "paid" {
  return isReservation && !txID ? "pending" : "paid";
}

async function enrichBooking(
  row: ReservationBusRow,
  payment: PaymentRow,
  profile: { firstName: string; lastName: string; phone: string | null },
): Promise<TravelerBooking | null> {
  const trips = await searchTripsSupabase({ reservationId: row.reservationId });
  const trip = trips[0];
  if (!trip) return null;

  const status = deriveStatus(
    row.isReservation,
    payment.txID,
    trip.departureTime,
  );

  return {
    _id: row.id,
    bookingReference: payment.reference,
    verifyToken: row.verifyToken ?? null,
    passengerName:
      row.passengerName?.trim() || `${profile.firstName} ${profile.lastName}`.trim(),
    passengerPhone:
      payment.phone !== "0000000000" ? payment.phone : profile.phone ?? undefined,
    seatNumber: row.seatNumber ?? undefined,
    totalPrice: row.price,
    currency: trip.currency,
    status,
    paymentStatus: derivePaymentStatus(row.isReservation, payment.txID),
    createdAt: row.createdAt,
    reservationId: row.reservationId,
    trip: {
      departureTime: trip.departureTime,
      arrivalTime: trip.arrivalTime,
      seatsAvailable: trip.seatsAvailable,
      totalSeats: trip.totalSeats,
    },
    originLoc: trip.originLoc,
    destLoc: trip.destLoc,
    company: trip.company,
    origin: trip.origin,
    destination: trip.destination,
    bus: trip.bus
      ? {
          name: trip.bus.name,
          busType: trip.bus.busType,
        }
      : null,
  };
}

export async function listMyBookingsSupabase(
  appUserId: string,
): Promise<TravelerBooking[]> {
  const { data: rows, error } = await supabase
    .from("ReservationBus")
    .select("id, reservationId, price, isReservation, createdAt, paymentId, passengerName, seatNumber, verifyToken")
    .eq("createdBy", appUserId)
    .eq("type", "voyage")
    .order("createdAt", { ascending: false });

  if (error) throw error;
  if (!rows?.length) return [];

  const paymentIds = rows.map((r) => r.paymentId as string);
  const { data: payments, error: paymentsError } = await supabase
    .from("Payment")
    .select("id, reference, phone, amount, txID")
    .in("id", paymentIds);

  if (paymentsError) throw paymentsError;

  const paymentMap = new Map(
    (payments ?? []).map((p) => [p.id as string, p as PaymentRow]),
  );

  const { data: profile, error: profileError } = await supabase
    .from("Users")
    .select("firstName, lastName, phone")
    .eq("id", appUserId)
    .maybeSingle();

  if (profileError) throw profileError;
  if (!profile) return [];

  const results: TravelerBooking[] = [];
  for (const row of rows) {
    const payment = paymentMap.get(row.paymentId as string);
    if (!payment) continue;
    if (
      !isIssuedTicket(
        row.isReservation as boolean,
        (payment as PaymentRow).txID,
      )
    ) {
      continue;
    }
    const booking = await enrichBooking(
      row as ReservationBusRow,
      payment,
      profile as { firstName: string; lastName: string; phone: string | null },
    );
    if (booking) results.push(booking);
  }

  return results;
}

export async function getTravelerBookingSupabase(
  bookingId: string,
  appUserId: string,
): Promise<TravelerBooking | null> {
  const { data: row, error } = await supabase
    .from("ReservationBus")
    .select("id, reservationId, price, isReservation, createdAt, paymentId, createdBy, passengerName, seatNumber, verifyToken")
    .eq("id", bookingId)
    .maybeSingle();

  if (error) throw error;
  if (!row || row.createdBy !== appUserId) return null;

  const { data: payment, error: paymentError } = await supabase
    .from("Payment")
    .select("id, reference, phone, amount, txID")
    .eq("id", row.paymentId as string)
    .maybeSingle();

  if (paymentError) throw paymentError;
  if (!payment) return null;

  if (
    !isIssuedTicket(
      row.isReservation as boolean,
      (payment as PaymentRow).txID,
    )
  ) {
    return null;
  }

  const { data: profile, error: profileError } = await supabase
    .from("Users")
    .select("firstName, lastName, phone")
    .eq("id", appUserId)
    .maybeSingle();

  if (profileError) throw profileError;
  if (!profile) return null;

  const booking = await enrichBooking(
    row as ReservationBusRow,
    payment as PaymentRow,
    profile as { firstName: string; lastName: string; phone: string | null },
  );

  if (!booking) return booking;

  const { data: progBus } = await supabase
    .from("Reservations")
    .select("trajetId")
    .eq("id", row.reservationId as string)
    .maybeSingle();

  if (progBus?.trajetId) {
    const { data: busLink } = await supabase
      .from("ProgrammationBus")
      .select("busId")
      .eq("trajetId", progBus.trajetId as string)
      .eq("isActive", true)
      .maybeSingle();

    if (busLink?.busId) {
      const { data: bus } = await supabase
        .from("Bus")
        .select("model, registrationNumber, capacity")
        .eq("id", busLink.busId as string)
        .maybeSingle();

      if (bus && booking.bus) {
        booking.bus = {
          name: (bus.model as string) ?? booking.bus.name,
          plateNumber: bus.registrationNumber as string,
          busType: booking.bus.busType ?? "Bus",
          capacity: bus.capacity as number,
        };
      }
    }
  }

  return booking;
}

/**
 * Émet un ticket payé en base — appeler uniquement après confirmation du paiement.
 * Aucun enregistrement n'est créé avant cet appel (anti-fraude).
 */
export async function issuePaidTravelerTicketSupabase(
  params: IssuePaidTicketParams,
): Promise<IssuePaidTicketResult> {
  const trip = await getTripDetailSupabase(params.reservationId);
  if (!trip) throw new Error("Trajet introuvable");
  if (trip.seatsAvailable <= 0) throw new Error("Plus de places disponibles");

  const { data: trajet, error: trajetError } = await supabase
    .from("ProgrammationTrajets")
    .select("depart, final")
    .eq("id", trip.trajetId)
    .maybeSingle();

  if (trajetError) throw trajetError;
  if (!trajet) throw new Error("Trajet introuvable");

  const { data: arret, error: arretError } = await supabase
    .from("ProgrammationTrajetArrets")
    .select("id, price")
    .eq("trajetId", trip.trajetId)
    .eq("fromGareId", trajet.depart as string)
    .eq("toGareId", trajet.final as string)
    .maybeSingle();

  if (arretError) throw arretError;
  if (!arret) throw new Error("Segment de trajet introuvable");

  let totalPrice = trip.priceAmount;
  if (params.promoId && params.discountAmount) {
    totalPrice = Math.max(0, totalPrice - params.discountAmount);
  }

  const reference = generateTicketRef();
  const phone = params.passengerPhone?.trim() || "0000000000";

  const { data: payment, error: paymentError } = await supabase
    .from("Payment")
    .insert({
      reference,
      phone,
      amount: totalPrice,
      txID: params.paymentTxId,
    })
    .select("id")
    .single();

  if (paymentError) throw paymentError;

  if (params.seatNumber?.trim()) {
    const { data: existingSeat, error: seatError } = await supabase
      .from("ReservationBus")
      .select("id")
      .eq("reservationId", params.reservationId)
      .eq("seatNumber", params.seatNumber.trim())
      .maybeSingle();

    if (seatError) throw seatError;
    if (existingSeat) throw new Error("Siège déjà vendu");
  }

  const { data: booking, error: bookingError } = await supabase
    .from("ReservationBus")
    .insert({
      type: "voyage",
      createdBy: params.appUserId,
      reservationId: params.reservationId,
      arretId: arret.id as string,
      price: totalPrice,
      isReservation: false,
      paymentId: payment.id as string,
      passengerName: params.passengerName.trim(),
      seatNumber: params.seatNumber?.trim() || null,
    })
    .select("id, verifyToken")
    .single();

  if (bookingError) throw bookingError;

  return {
    bookingId: booking.id as string,
    reference,
    verifyToken: (booking.verifyToken as string | null) ?? null,
    totalPrice,
    currency: trip.currency,
  };
}

export async function cancelTravelerBookingSupabase(
  bookingId: string,
  appUserId: string,
): Promise<void> {
  const { data: row, error } = await supabase
    .from("ReservationBus")
    .select("id, createdBy, isReservation")
    .eq("id", bookingId)
    .maybeSingle();

  if (error) throw error;
  if (!row || row.createdBy !== appUserId) {
    throw new Error("Réservation introuvable");
  }
  if (!row.isReservation) {
    throw new Error("Impossible d'annuler un billet confirmé");
  }

  const { error: deleteError } = await supabase
    .from("ReservationBus")
    .delete()
    .eq("id", bookingId);

  if (deleteError) throw deleteError;
}
