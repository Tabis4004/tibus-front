import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export type IssueTicketInput = {
  reservationId: string;
  appUserId: string;
  passengerName?: string;
  passengerPhone?: string;
  seatNumber?: string;
  parcelCount?: number;
  parcelWeight?: number;
  parcelAmount?: number;
  saleChannel?: "traveler" | "seller_reservation" | "counter_sale";
  promoId?: string;
  discountAmount?: number;
  loyaltyPointsRedeemed?: number;
  loyaltyDiscountAmount?: number;
  platformLoyaltyPointsRedeemed?: number;
  platformLoyaltyDiscountAmount?: number;
  paymentTxId: string;
  platformMarginPercent?: number;
  travelerPaidTotal?: number;
};

function generateTicketRef() {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let ref = "TB-";
  for (let i = 0; i < 8; i++) {
    ref += chars[Math.floor(Math.random() * chars.length)];
  }
  return ref;
}

export async function countIssuedSeats(
  admin: SupabaseClient,
  reservationId: string,
): Promise<number> {
  const { data: rows, error } = await admin
    .from("ReservationBus")
    .select("isReservation, paymentId")
    .eq("reservationId", reservationId)
    .eq("type", "voyage");

  if (error) throw error;
  if (!rows?.length) return 0;

  const paymentIds = rows.map((r) => r.paymentId as string);
  const { data: payments, error: payError } = await admin
    .from("Payment")
    .select("id, txID")
    .in("id", paymentIds);

  if (payError) throw payError;

  const paymentTx = new Map(
    (payments ?? []).map((p) => [p.id as string, p.txID as string | null]),
  );

  return rows.filter((r) => {
    const txID = paymentTx.get(r.paymentId as string);
    return !r.isReservation || Boolean(txID);
  }).length;
}

export async function issueTicketAfterPayment(
  admin: SupabaseClient,
  input: IssueTicketInput,
) {
  const txKey = input.paymentTxId;

  const { data: existingPayment, error: existingPayError } = await admin
    .from("Payment")
    .select("id, reference")
    .eq("txID", txKey)
    .maybeSingle();

  if (existingPayError) throw existingPayError;

  if (existingPayment) {
    const { data: existingBooking, error: existingBookingError } = await admin
      .from("ReservationBus")
      .select("id")
      .eq("paymentId", existingPayment.id as string)
      .maybeSingle();

    if (existingBookingError) throw existingBookingError;
    if (existingBooking) {
      return {
        bookingId: existingBooking.id as string,
        reference: existingPayment.reference as string,
        alreadyIssued: true,
      };
    }
  }

  const { data: reservation, error: reservationError } = await admin
    .from("Reservations")
    .select("id, capacity, trajetId")
    .eq("id", input.reservationId)
    .maybeSingle();

  if (reservationError) throw reservationError;
  if (!reservation) throw new Error("Départ introuvable");

  const booked = await countIssuedSeats(admin, input.reservationId);
  const capacity = reservation.capacity as number;
  if (booked >= capacity) {
    throw new Error("Plus de places disponibles");
  }

  const seatNumber = input.seatNumber?.trim() || null;
  if (seatNumber) {
    const { data: existingSeat, error: seatError } = await admin
      .from("ReservationBus")
      .select("id")
      .eq("reservationId", input.reservationId)
      .eq("seatNumber", seatNumber)
      .maybeSingle();

    if (seatError) throw seatError;
    if (existingSeat) {
      throw new Error("Siège déjà vendu");
    }
  }

  const { data: trajet, error: trajetError } = await admin
    .from("ProgrammationTrajets")
    .select("id, depart, final")
    .eq("id", reservation.trajetId as string)
    .maybeSingle();

  if (trajetError) throw trajetError;
  if (!trajet) throw new Error("Trajet introuvable");

  const { data: arret, error: arretError } = await admin
    .from("ProgrammationTrajetArrets")
    .select("id, price")
    .eq("trajetId", trajet.id as string)
    .eq("fromGareId", trajet.depart as string)
    .eq("toGareId", trajet.final as string)
    .maybeSingle();

  if (arretError) throw arretError;
  if (!arret) throw new Error("Segment introuvable");

  const { data: originGare, error: originGareError } = await admin
    .from("Gares")
    .select("companyId")
    .eq("id", trajet.depart as string)
    .maybeSingle();

  if (originGareError) throw originGareError;
  const companyId = originGare?.companyId as string | undefined;
  if (!companyId) throw new Error("Compagnie introuvable");

  let totalPrice = arret.price as number;
  if (input.promoId && input.discountAmount) {
    totalPrice = Math.max(0, totalPrice - input.discountAmount);
  }
  if (input.loyaltyDiscountAmount) {
    totalPrice = Math.max(0, totalPrice - input.loyaltyDiscountAmount);
  }
  if (input.platformLoyaltyDiscountAmount) {
    totalPrice = Math.max(0, totalPrice - input.platformLoyaltyDiscountAmount);
  }
  const parcelAmount = Math.max(0, input.parcelAmount ?? 0);
  totalPrice += parcelAmount;

  const saleChannel = input.saleChannel ?? "traveler";
  if (saleChannel === "traveler") {
    const { data: existingTravelerTicket, error: existingTravelerError } = await admin
      .from("ReservationBus")
      .select("id")
      .eq("reservationId", input.reservationId)
      .eq("createdBy", input.appUserId)
      .eq("type", "voyage")
      .or('saleChannel.is.null,saleChannel.eq.traveler')
      .maybeSingle();

    if (existingTravelerError) throw existingTravelerError;
    if (existingTravelerTicket) {
      throw new Error("Vous avez deja un billet pour ce depart");
    }
  }

  const { data: guaranteeCheck, error: guaranteeCheckError } = await admin.rpc(
    "check_company_guarantee_sufficient",
    {
      p_company_id: companyId,
      p_amount: totalPrice,
      p_sale_channel: saleChannel,
    },
  );

  if (guaranteeCheckError) throw guaranteeCheckError;
  const guaranteePayload = (guaranteeCheck ?? {}) as {
    required?: boolean;
    sufficient?: boolean;
    balance?: number;
  };
  if (guaranteePayload.required && !guaranteePayload.sufficient) {
    throw new Error(
      `Fond de garantie insuffisant (solde: ${guaranteePayload.balance ?? 0}, requis: ${totalPrice})`,
    );
  }

  const reference = generateTicketRef();
  const phone = input.passengerPhone?.trim() || "0000000000";

  const { data: payment, error: paymentError } = await admin
    .from("Payment")
    .insert({
      reference,
      phone,
      amount: totalPrice,
      txID: txKey,
    })
    .select("id")
    .single();

  if (paymentError) throw paymentError;

  const { data: booking, error: bookingError } = await admin
    .from("ReservationBus")
    .insert({
      type: "voyage",
      createdBy: input.appUserId,
      reservationId: input.reservationId,
      arretId: arret.id as string,
      price: totalPrice,
      isReservation: false,
      paymentId: payment.id as string,
      passengerName: input.passengerName?.trim() || null,
      seatNumber,
      parcelCount: input.parcelCount && input.parcelCount > 0 ? input.parcelCount : null,
      parcelWeight: input.parcelWeight && input.parcelWeight > 0 ? input.parcelWeight : null,
      parcelAmount: parcelAmount > 0 ? parcelAmount : null,
      exceedColisAmount: parcelAmount > 0 ? parcelAmount : null,
      saleChannel,
    })
    .select("id")
    .single();

  if (bookingError) throw bookingError;

  const { error: commissionCaptureError } = await admin.rpc(
    "capture_booking_platform_commission",
    {
      p_booking_id: booking.id as string,
      p_nominal_amount: totalPrice,
      p_company_id: companyId,
      p_sale_channel: saleChannel,
      p_commission_rate: input.platformMarginPercent ?? null,
      p_traveler_paid_total: input.travelerPaidTotal ?? null,
    },
  );
  if (commissionCaptureError) {
    console.warn("capture_booking_platform_commission:", commissionCaptureError.message);
  }

  const { error: guaranteeDeductError } = await admin.rpc("deduct_company_guarantee_fund", {
    p_company_id: companyId,
    p_amount: totalPrice,
    p_sale_channel: saleChannel,
    p_booking_id: booking.id as string,
    p_reference: reference,
    p_author_id: input.appUserId,
  });

  if (guaranteeDeductError) {
    await admin.from("ReservationBus").delete().eq("id", booking.id as string);
    await admin.from("Payment").delete().eq("id", payment.id as string);
    throw guaranteeDeductError;
  }

  if (saleChannel === "traveler") {
    const { error: loyaltyError } = await admin.rpc("process_loyalty_on_ticket", {
      p_user_id: input.appUserId,
      p_company_id: companyId,
      p_booking_id: booking.id as string,
      p_cash_paid: totalPrice,
      p_points_redeemed: input.loyaltyPointsRedeemed ?? 0,
      p_loyalty_user_id: input.appUserId,
    });
    if (loyaltyError) throw loyaltyError;

    const { error: platformLoyaltyError } = await admin.rpc(
      "process_platform_loyalty_on_ticket",
      {
        p_user_id: input.appUserId,
        p_company_id: companyId,
        p_booking_id: booking.id as string,
        p_cash_paid: totalPrice,
        p_points_redeemed: input.platformLoyaltyPointsRedeemed ?? 0,
      },
    );
    if (platformLoyaltyError) throw platformLoyaltyError;
  }

  if (input.promoId) {
    const { error: promoError } = await admin.rpc("increment_promo_usage", {
      p_promo_id: input.promoId,
    });
    if (promoError) throw promoError;
  }

  return {
    bookingId: booking.id as string,
    reference,
    alreadyIssued: false,
  };
}


export type PaymentMetadataTraveler = {
  passengerName?: string;
  passengerPhone?: string;
  seatNumber?: string;
  parcelCount?: number;
  parcelWeight?: number;
  parcelAmount?: number;
};

function parseMetadataTravelers(meta: Record<string, string>): PaymentMetadataTraveler[] {
  if (meta.travelers) {
    try {
      const parsed = JSON.parse(meta.travelers) as PaymentMetadataTraveler[];
      if (Array.isArray(parsed) && parsed.length > 0) return parsed;
    } catch {
      // Fallback to single traveler fields below.
    }
  }

  return [{
    passengerName: meta.passengerName || undefined,
    passengerPhone: meta.passengerPhone || undefined,
    seatNumber: meta.seatNumber || undefined,
  }];
}

export async function issueTicketsFromPaymentMetadata(
  admin: SupabaseClient,
  meta: Record<string, string>,
  paymentTxId: string,
) {
  const travelers = parseMetadataTravelers(meta);
  const issued = [];
  const saleChannel = meta.channel === "seller_reservation" ? "seller_reservation" : "traveler";

  for (let i = 0; i < travelers.length; i++) {
    const traveler = travelers[i];
    const ticket = await issueTicketAfterPayment(admin, {
      reservationId: meta.reservationId,
      appUserId: meta.appUserId,
      passengerName: traveler.passengerName || meta.passengerName || undefined,
      passengerPhone: traveler.passengerPhone || meta.passengerPhone || undefined,
      seatNumber: traveler.seatNumber || undefined,
      parcelCount: Number(traveler.parcelCount ?? 0) || 0,
      parcelWeight: Number(traveler.parcelWeight ?? 0) || 0,
      parcelAmount: Number(traveler.parcelAmount ?? 0) || 0,
      promoId: travelers.length === 1 ? (meta.promoId || undefined) : undefined,
      discountAmount: travelers.length === 1 && meta.discountAmount
        ? Number(meta.discountAmount)
        : undefined,
      loyaltyPointsRedeemed: travelers.length === 1 && meta.loyaltyPointsRedeemed
        ? Number(meta.loyaltyPointsRedeemed)
        : undefined,
      loyaltyDiscountAmount: travelers.length === 1 && meta.loyaltyDiscountAmount
        ? Number(meta.loyaltyDiscountAmount)
        : undefined,
      platformLoyaltyPointsRedeemed: travelers.length === 1 && meta.platformLoyaltyPointsRedeemed
        ? Number(meta.platformLoyaltyPointsRedeemed)
        : undefined,
      platformLoyaltyDiscountAmount: travelers.length === 1 && meta.platformLoyaltyDiscountAmount
        ? Number(meta.platformLoyaltyDiscountAmount)
        : undefined,
      paymentTxId: travelers.length === 1 ? paymentTxId : `${paymentTxId}:${i + 1}`,
      saleChannel,
      platformMarginPercent: meta.platformMarginPercent
        ? Number(meta.platformMarginPercent)
        : undefined,
      travelerPaidTotal: meta.totalAmount ? Number(meta.totalAmount) : undefined,
    });
    issued.push(ticket);
  }

  return issued;
}

export function createAdminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    throw new Error("SUPABASE_URL ou SUPABASE_SERVICE_ROLE_KEY manquant");
  }
  return createClient(url, serviceKey);
}

export async function resolveAppUserId(
  admin: SupabaseClient,
  authUserId: string,
): Promise<string | null> {
  const { data, error } = await admin
    .from("users")
    .select("id")
    .eq("auth_user_id", authUserId)
    .maybeSingle();

  if (error) throw error;
  return (data?.id as string) ?? null;
}
