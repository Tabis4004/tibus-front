import { getUserFromRequest } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { createFedaPayCheckout } from "../_shared/fedapay.ts";
import { countIssuedSeats, createAdminClient, resolveAppUserId } from "../_shared/issue-ticket.ts";

type PaymentTraveler = {
  passengerName?: string;
  passengerPhone?: string;
  seatNumber?: string;
  parcelCount?: number;
  parcelWeight?: number;
  parcelAmount?: number;
};

type InitBody = {
  reservationId?: string;
  passengerName?: string;
  passengerPhone?: string;
  seatNumber?: string;
  travelers?: PaymentTraveler[];
  channel?: "traveler" | "seller_reservation";
  promoId?: string;
  discountAmount?: number;
  loyaltyPointsRedeemed?: number;
  loyaltyDiscountAmount?: number;
  platformLoyaltyPointsRedeemed?: number;
  platformLoyaltyDiscountAmount?: number;
  paymentMethod?: string;
  paymentNetwork?: string;
  successUrl?: string;
  errorUrl?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user, error: authError } = await getUserFromRequest(req);
    if (authError || !user) {
      return jsonResponse({ error: authError ?? "Session invalide" }, 401);
    }

    const body = (await req.json()) as InitBody;
    const {
      reservationId,
      passengerName,
      passengerPhone,
      seatNumber,
      travelers,
      channel,
      promoId,
      discountAmount,
      loyaltyPointsRedeemed,
      loyaltyDiscountAmount,
      platformLoyaltyPointsRedeemed,
      platformLoyaltyDiscountAmount,
      successUrl,
    } = body;

    const normalizedTravelers = (travelers?.length
      ? travelers
      : [{ passengerName, passengerPhone, seatNumber }]
    )
      .map((traveler) => ({
        passengerName: traveler.passengerName?.trim() ?? "",
        passengerPhone: traveler.passengerPhone?.trim() ?? "",
        seatNumber: traveler.seatNumber?.trim() ?? "",
        parcelCount: Math.max(0, Number(traveler.parcelCount ?? 0) || 0),
        parcelWeight: Math.max(0, Number(traveler.parcelWeight ?? 0) || 0),
        parcelAmount: Math.max(0, Number(traveler.parcelAmount ?? 0) || 0),
      }))
      .filter((traveler) => traveler.passengerName);

    if (!reservationId || !successUrl || normalizedTravelers.length === 0) {
      return jsonResponse({ error: "Paramètres manquants" }, 400);
    }
    if (normalizedTravelers.some((traveler) => !traveler.passengerPhone)) {
      return jsonResponse({ error: "Numéro de téléphone requis pour chaque voyageur" }, 400);
    }

    const saleChannel = channel === "seller_reservation" ? "seller_reservation" : "traveler";

    const admin = createAdminClient();
    const appUserId = await resolveAppUserId(admin, user.id);
    if (!appUserId) {
      return jsonResponse({ error: "Profil utilisateur introuvable" }, 404);
    }

    const { data: reservation, error: reservationError } = await admin
      .from("Reservations")
      .select("id, capacity, trajetId")
      .eq("id", reservationId)
      .maybeSingle();

    if (reservationError) throw reservationError;
    if (!reservation) {
      return jsonResponse({ error: "Départ introuvable" }, 404);
    }

    const booked = await countIssuedSeats(admin, reservationId);
    if (booked + normalizedTravelers.length > (reservation.capacity as number)) {
      return jsonResponse({ error: "Plus de places disponibles", code: "SOLD_OUT" }, 409);
    }

    const selectedSeats = normalizedTravelers
      .map((traveler) => traveler.seatNumber)
      .filter((seat) => Boolean(seat));
    if (new Set(selectedSeats).size !== selectedSeats.length) {
      return jsonResponse({ error: "Deux voyageurs ne peuvent pas avoir le même siège", code: "SEAT_TAKEN" }, 409);
    }

    if (selectedSeats.length > 0) {
      const { data: existingSeats, error: seatError } = await admin
        .from("ReservationBus")
        .select("id, seatNumber")
        .eq("reservationId", reservationId)
        .in("seatNumber", selectedSeats);

      if (seatError) throw seatError;
      if (existingSeats?.length) {
        return jsonResponse({ error: "Siège déjà vendu", code: "SEAT_TAKEN" }, 409);
      }
    }

    if (saleChannel === "traveler") {
      const { data: existingTravelerTicket, error: existingTravelerError } = await admin
        .from("ReservationBus")
        .select("id")
        .eq("reservationId", reservationId)
        .eq("createdBy", appUserId)
        .eq("type", "voyage")
        .or('saleChannel.is.null,saleChannel.eq.traveler')
        .maybeSingle();

      if (existingTravelerError) throw existingTravelerError;
      if (existingTravelerTicket) {
        return jsonResponse({ error: "Vous avez déjà un billet pour ce départ", code: "DUPLICATE_TRAVELER_BOOKING" }, 409);
      }
    }

    const { data: trajet, error: trajetError } = await admin
      .from("ProgrammationTrajets")
      .select("id, depart, final")
      .eq("id", reservation.trajetId as string)
      .maybeSingle();

    if (trajetError) throw trajetError;
    if (!trajet) {
      return jsonResponse({ error: "Trajet introuvable" }, 404);
    }

    const { data: arret, error: arretError } = await admin
      .from("ProgrammationTrajetArrets")
      .select("price")
      .eq("trajetId", trajet.id as string)
      .eq("fromGareId", trajet.depart as string)
      .eq("toGareId", trajet.final as string)
      .maybeSingle();

    if (arretError) throw arretError;
    if (!arret) {
      return jsonResponse({ error: "Tarif introuvable" }, 404);
    }

    const basePrice = arret.price as number;

    const { data: originGare, error: originGareError } = await admin
      .from("Gares")
      .select("companyId")
      .eq("id", trajet.depart as string)
      .maybeSingle();

    if (originGareError) throw originGareError;
    const companyId = originGare?.companyId as string | undefined;
    if (!companyId) {
      return jsonResponse({ error: "Compagnie introuvable" }, 404);
    }

    let resolvedLoyaltyPoints = 0;
    let resolvedLoyaltyDiscount = 0;
    let resolvedPlatformLoyaltyPoints = 0;
    let resolvedPlatformLoyaltyDiscount = 0;

    const nominalAmount = (() => {
      let total = normalizedTravelers.reduce(
        (sum, traveler) => sum + basePrice + traveler.parcelAmount,
        0,
      );
      if (saleChannel === "traveler" && promoId && discountAmount) {
        total = Math.max(0, total - discountAmount);
      }
      return total;
    })();

    let payableNominal = nominalAmount;

    if (
      saleChannel === "traveler"
      && loyaltyPointsRedeemed
      && loyaltyPointsRedeemed > 0
    ) {
      const ticketPriceForLoyalty = Math.max(
        0,
        basePrice + (normalizedTravelers[0]?.parcelAmount ?? 0)
          - (promoId && discountAmount ? discountAmount : 0),
      );
      const { data: loyaltyCheck, error: loyaltyError } = await admin.rpc(
        "validate_loyalty_redemption",
        {
          p_company_id: companyId,
          p_ticket_price: ticketPriceForLoyalty,
          p_points: loyaltyPointsRedeemed,
          p_user_id: appUserId,
        },
      );
      if (loyaltyError) throw loyaltyError;
      const loyaltyPayload = (loyaltyCheck ?? {}) as {
        valid?: boolean;
        discountAmount?: number;
        pointsRedeemed?: number;
        error?: string;
      };
      if (!loyaltyPayload.valid) {
        return jsonResponse({
          error: loyaltyPayload.error ?? "Utilisation des points impossible",
          code: "LOYALTY_INVALID",
        }, 400);
      }
      resolvedLoyaltyPoints = Number(loyaltyPayload.pointsRedeemed ?? loyaltyPointsRedeemed);
      resolvedLoyaltyDiscount = Number(loyaltyPayload.discountAmount ?? 0);
      if (
        loyaltyDiscountAmount != null
        && Math.abs(resolvedLoyaltyDiscount - Number(loyaltyDiscountAmount)) > 1
      ) {
        return jsonResponse({ error: "Montant fidélité invalide", code: "LOYALTY_INVALID" }, 400);
      }
      payableNominal = Math.max(0, nominalAmount - resolvedLoyaltyDiscount);
    }

    if (
      saleChannel === "traveler"
      && platformLoyaltyPointsRedeemed
      && platformLoyaltyPointsRedeemed > 0
    ) {
      const ticketPriceForPlatform = Math.max(
        0,
        basePrice + (normalizedTravelers[0]?.parcelAmount ?? 0)
          - (promoId && discountAmount ? discountAmount : 0)
          - resolvedLoyaltyDiscount,
      );
      const { data: platformLoyaltyCheck, error: platformLoyaltyError } = await admin.rpc(
        "validate_platform_loyalty_redemption",
        {
          p_ticket_price: ticketPriceForPlatform,
          p_points: platformLoyaltyPointsRedeemed,
          p_user_id: appUserId,
        },
      );
      if (platformLoyaltyError) throw platformLoyaltyError;
      const platformPayload = (platformLoyaltyCheck ?? {}) as {
        valid?: boolean;
        discountAmount?: number;
        pointsRedeemed?: number;
        error?: string;
      };
      if (!platformPayload.valid) {
        return jsonResponse({
          error: platformPayload.error ?? "Utilisation des points plateforme impossible",
          code: "PLATFORM_LOYALTY_INVALID",
        }, 400);
      }
      resolvedPlatformLoyaltyPoints = Number(
        platformPayload.pointsRedeemed ?? platformLoyaltyPointsRedeemed,
      );
      resolvedPlatformLoyaltyDiscount = Number(platformPayload.discountAmount ?? 0);
      if (
        platformLoyaltyDiscountAmount != null
        && Math.abs(resolvedPlatformLoyaltyDiscount - Number(platformLoyaltyDiscountAmount)) > 1
      ) {
        return jsonResponse({
          error: "Montant fidélité plateforme invalide",
          code: "PLATFORM_LOYALTY_INVALID",
        }, 400);
      }
      payableNominal = Math.max(0, payableNominal - resolvedPlatformLoyaltyDiscount);
    }

    const { data: guaranteeCheck, error: guaranteeCheckError } = await admin.rpc(
      "check_company_guarantee_sufficient",
      {
        p_company_id: companyId,
        p_amount: payableNominal,
        p_sale_channel: saleChannel,
      },
    );

    if (guaranteeCheckError) throw guaranteeCheckError;
    const guaranteePayload = (guaranteeCheck ?? {}) as {
      required?: boolean;
      sufficient?: boolean;
      balance?: number;
      currency?: string;
    };
    if (guaranteePayload.required && !guaranteePayload.sufficient) {
      return jsonResponse({
        error: `Réservation indisponible : fond de garantie insuffisant (solde ${guaranteePayload.balance ?? 0} ${guaranteePayload.currency ?? "XOF"}, requis ${nominalAmount}).`,
        code: "GUARANTEE_FUND_INSUFFICIENT",
        balance: guaranteePayload.balance ?? 0,
        required: nominalAmount,
        currency: guaranteePayload.currency ?? "XOF",
      }, 409);
    }

    const paymentMethod = (body.paymentMethod ?? "mobile_money").trim().toLowerCase();
    const paymentNetwork = (body.paymentNetwork ?? "unknown").trim().toLowerCase();
    const { data: paymentCalc, error: paymentCalcError } = await admin.rpc(
      "calculate_traveler_payment_total",
      {
        p_nominal_amount: payableNominal,
        p_company_id: companyId,
        p_gateway: "fedapay",
        p_method: paymentMethod,
        p_network: paymentNetwork,
        p_trip_margin_percent: null,
      },
    );

    if (paymentCalcError) {
      const message = paymentCalcError.message ?? "Calcul paiement impossible";
      if (message.includes("Configuration frais gateway")) {
        return jsonResponse({
          error: message.includes("Config existante")
            ? `Frais FedaPay introuvables pour ce trajet. ${message}`
            : "Frais de paiement non configurés pour ce pays. Vérifiez gateway=fedapay, méthode=mobile_money et le pays de la compagnie dans l'admin.",
          code: "GATEWAY_FEE_NOT_CONFIGURED",
        }, 422);
      }
      if (message.includes("Compagnie sans pays")) {
        return jsonResponse({
          error: "La compagnie de ce trajet n'a pas de pays associé (countryId). Corrigez la fiche compagnie dans l'admin.",
          code: "COMPANY_COUNTRY_MISSING",
        }, 422);
      }
      throw paymentCalcError;
    }

    const calc = paymentCalc as {
      totalAmount?: unknown;
      platformNetAmount?: unknown;
      gatewayAmount?: unknown;
      feeMode?: unknown;
    } | null;

    // FedaPay : le champ API `amount` = V (M+MX%). Les frais Y sont ajoutés par FedaPay au checkout.
    const fedapayApiAmount = Number(
      calc?.gatewayAmount ?? calc?.platformNetAmount ?? calc?.totalAmount ?? nominalAmount,
    );
    const travelerCheckoutAmount = Number(calc?.totalAmount ?? fedapayApiAmount);

    const firstTraveler = normalizedTravelers[0];
    const nameParts = firstTraveler.passengerName.split(/\s+/);
    const firstname = nameParts[0] ?? firstTraveler.passengerName;
    const lastname = nameParts.length > 1 ? nameParts.slice(1).join(" ") : firstname;

    const checkout = await createFedaPayCheckout({
      amount: fedapayApiAmount,
      description: `Billet Tibus`,
      callbackUrl: successUrl,
      customer: {
        firstname,
        lastname,
        email: user.email ?? "customer@tibus.app",
        phone: firstTraveler.passengerPhone,
      },
      metadata: {
        type: "supabase_ticket_payment",
        reservationId,
        appUserId,
        passengerName: firstTraveler.passengerName,
        passengerPhone: firstTraveler.passengerPhone,
        seatNumber: firstTraveler.seatNumber,
        travelers: JSON.stringify(normalizedTravelers),
        channel: saleChannel,
        promoId: saleChannel === "traveler" ? (promoId ?? "") : "",
        discountAmount: discountAmount ? String(discountAmount) : "",
        loyaltyPointsRedeemed: saleChannel === "traveler" && resolvedLoyaltyPoints > 0
          ? String(resolvedLoyaltyPoints)
          : "",
        loyaltyDiscountAmount: saleChannel === "traveler" && resolvedLoyaltyDiscount > 0
          ? String(resolvedLoyaltyDiscount)
          : "",
        platformLoyaltyPointsRedeemed: saleChannel === "traveler" && resolvedPlatformLoyaltyPoints > 0
          ? String(resolvedPlatformLoyaltyPoints)
          : "",
        platformLoyaltyDiscountAmount: saleChannel === "traveler" && resolvedPlatformLoyaltyDiscount > 0
          ? String(resolvedPlatformLoyaltyDiscount)
          : "",
        nominalAmount: String(payableNominal),
        totalAmount: String(travelerCheckoutAmount),
        fedapayApiAmount: String(fedapayApiAmount),
        paymentMethod,
        paymentNetwork,
        companyId,
      },
    });

    return jsonResponse({
      checkoutUrl: checkout.checkoutUrl,
      reference: checkout.reference,
      transactionId: checkout.transactionId,
      amount: travelerCheckoutAmount,
      fedapayApiAmount,
      nominalAmount,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Erreur FedaPay";
    return jsonResponse({ error: message }, 500);
  }
});
