import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { createAdminClient } from "../_shared/issue-ticket.ts";
import { resolvePartnerAuth } from "../_shared/partner-auth.ts";
import {
  dispatchPartnerWebhooks,
  type PartnerWebhookEvent,
} from "../_shared/partner-webhooks.ts";

type GareRef = {
  tibusGareId?: string;
  externalGareId?: string;
};

type UpsertDepartureBody = {
  externalDepartureId?: string;
  departureAt?: string;
  capacity?: number;
  price?: number;
  kilometrage?: number;
  origin?: GareRef;
  destination?: GareRef;
  departGareId?: string;
  finalGareId?: string;
  payload?: Record<string, unknown>;
};

type GareMappingBody = {
  externalGareId?: string;
  tibusGareId?: string;
  externalName?: string;
};

type CreateBookingBody = {
  externalDepartureId?: string;
  externalBookingId?: string;
  passengerName?: string;
  passengerPhone?: string;
  seatNumber?: string;
  mode?: "sale" | "hold";
  holdMinutes?: number;
  externalPaymentRef?: string;
  price?: number;
  payload?: Record<string, unknown>;
};

type ConfirmBookingBody = {
  externalPaymentRef?: string;
};

function routePath(req: Request): string {
  const url = new URL(req.url);
  const marker = "/partner-itinerary-api";
  const idx = url.pathname.indexOf(marker);
  const suffix = idx >= 0 ? url.pathname.slice(idx + marker.length) : url.pathname;
  return suffix.replace(/\/+$/, "") || "/";
}

async function resolveGareId(
  admin: ReturnType<typeof createAdminClient>,
  companyId: string,
  externalSystem: string,
  ref: GareRef | undefined,
  fallbackId?: string,
): Promise<string> {
  const { data, error } = await admin.rpc("partner_resolve_gare_id", {
    p_company_id: companyId,
    p_external_system: externalSystem,
    p_external_gare_id: ref?.externalGareId ?? null,
    p_tibus_gare_id: ref?.tibusGareId ?? fallbackId ?? null,
  });

  if (error) throw new Error(error.message);
  return data as string;
}

async function emitWebhook(
  companyId: string,
  externalSystem: string,
  eventType: PartnerWebhookEvent,
  payload: Record<string, unknown>,
) {
  try {
    await dispatchPartnerWebhooks({ companyId, externalSystem, eventType, payload });
  } catch {
    // Ne pas bloquer la réponse API si le webhook échoue.
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const path = routePath(req);

    if (req.method === "GET" && (path === "/" || path === "/v1/health")) {
      return jsonResponse({ ok: true, service: "partner-itinerary-api", version: 2 });
    }

    const { context, error: authError } = await resolvePartnerAuth(req);
    if (!context) {
      return jsonResponse({ error: authError ?? "Non autorise" }, 401);
    }

    const admin = createAdminClient();

    if (req.method === "POST" && path === "/v1/gares/mappings") {
      const body = (await req.json()) as GareMappingBody;
      if (!body.externalGareId || !body.tibusGareId) {
        return jsonResponse({ error: "externalGareId et tibusGareId requis" }, 400);
      }

      const { data, error } = await admin.rpc("partner_upsert_gare_mapping", {
        p_company_id: context.companyId,
        p_external_system: context.externalSystem,
        p_external_gare_id: body.externalGareId,
        p_gare_id: body.tibusGareId,
        p_external_name: body.externalName ?? null,
      });

      if (error) return jsonResponse({ error: error.message }, 400);
      return jsonResponse({ mappingId: data, externalGareId: body.externalGareId });
    }

    if (req.method === "GET" && path === "/v1/gares/mappings") {
      const { data, error } = await admin
        .from("PartnerGareMappings")
        .select("id, externalGareId, gareId, externalName, createdAt")
        .eq("companyId", context.companyId)
        .eq("externalSystem", context.externalSystem)
        .order("createdAt", { ascending: false });

      if (error) return jsonResponse({ error: error.message }, 400);
      return jsonResponse({ mappings: data ?? [] });
    }

    if (req.method === "PUT" && path === "/v1/departures") {
      const body = (await req.json()) as UpsertDepartureBody;
      if (!body.externalDepartureId || !body.departureAt || !body.capacity) {
        return jsonResponse({
          error: "externalDepartureId, departureAt et capacity requis",
        }, 400);
      }

      const departGareId = await resolveGareId(
        admin,
        context.companyId,
        context.externalSystem,
        body.origin,
        body.departGareId,
      );
      const finalGareId = await resolveGareId(
        admin,
        context.companyId,
        context.externalSystem,
        body.destination,
        body.finalGareId,
      );

      const { data, error } = await admin.rpc("partner_upsert_departure", {
        p_company_id: context.companyId,
        p_external_system: context.externalSystem,
        p_external_departure_id: body.externalDepartureId,
        p_depart_gare_id: departGareId,
        p_final_gare_id: finalGareId,
        p_departure_at: body.departureAt,
        p_capacity: body.capacity,
        p_price: body.price ?? 0,
        p_kilometrage: body.kilometrage ?? null,
        p_payload: body.payload ?? null,
      });

      if (error) return jsonResponse({ error: error.message }, 400);

      const row = Array.isArray(data) ? data[0] : null;
      if (!row) return jsonResponse({ error: "Synchronisation impossible" }, 500);

      const availability = await admin.rpc("partner_get_departure_availability", {
        p_company_id: context.companyId,
        p_external_system: context.externalSystem,
        p_external_departure_id: body.externalDepartureId,
      });

      const response = {
        externalDepartureId: body.externalDepartureId,
        tibusReservationId: row.reservation_id,
        tibusTrajetId: row.trajet_id,
        created: row.created,
        availability: availability.data ?? null,
      };

      await emitWebhook(context.companyId, context.externalSystem, "departure.synced", response);

      return jsonResponse(response);
    }

    if (req.method === "GET" && path === "/v1/departures") {
      const url = new URL(req.url);
      const from = url.searchParams.get("from") ?? new Date().toISOString();
      const to = url.searchParams.get("to");
      const limit = Number(url.searchParams.get("limit") ?? "100");

      const { data, error } = await admin.rpc("partner_list_departures", {
        p_company_id: context.companyId,
        p_external_system: context.externalSystem,
        p_from: from,
        p_to: to,
        p_limit: Number.isFinite(limit) ? limit : 100,
      });

      if (error) return jsonResponse({ error: error.message }, 400);
      return jsonResponse({ departures: data ?? [] });
    }

    const availabilityMatch = path.match(/^\/v1\/departures\/([^/]+)\/availability$/);
    if (req.method === "GET" && availabilityMatch) {
      const externalDepartureId = decodeURIComponent(availabilityMatch[1]);
      const { data, error } = await admin.rpc("partner_get_departure_availability", {
        p_company_id: context.companyId,
        p_external_system: context.externalSystem,
        p_external_departure_id: externalDepartureId,
      });

      if (error) return jsonResponse({ error: error.message }, 404);
      return jsonResponse(data);
    }

    if (req.method === "POST" && path === "/v1/bookings") {
      const body = (await req.json()) as CreateBookingBody;
      if (!body.externalDepartureId || !body.externalBookingId || !body.passengerName) {
        return jsonResponse({
          error: "externalDepartureId, externalBookingId et passengerName requis",
        }, 400);
      }

      const { data, error } = await admin.rpc("partner_create_booking", {
        p_company_id: context.companyId,
        p_external_system: context.externalSystem,
        p_external_departure_id: body.externalDepartureId,
        p_external_booking_id: body.externalBookingId,
        p_passenger_name: body.passengerName,
        p_passenger_phone: body.passengerPhone ?? null,
        p_seat_number: body.seatNumber ?? null,
        p_mode: body.mode ?? "sale",
        p_hold_minutes: body.holdMinutes ?? 15,
        p_external_payment_ref: body.externalPaymentRef ?? null,
        p_price_override: body.price ?? null,
        p_payload: body.payload ?? null,
      });

      if (error) return jsonResponse({ error: error.message }, 400);

      const eventType: PartnerWebhookEvent =
        body.mode === "hold" ? "booking.created" : "booking.created";
      await emitWebhook(context.companyId, context.externalSystem, eventType, data as Record<string, unknown>);

      return jsonResponse(data, 201);
    }

    const bookingMatch = path.match(/^\/v1\/bookings\/([^/]+)$/);
    if (bookingMatch) {
      const externalBookingId = decodeURIComponent(bookingMatch[1]);

      if (req.method === "GET") {
        const { data, error } = await admin.rpc("partner_get_booking", {
          p_company_id: context.companyId,
          p_external_system: context.externalSystem,
          p_external_booking_id: externalBookingId,
        });
        if (error) return jsonResponse({ error: error.message }, 404);
        return jsonResponse(data);
      }

      if (req.method === "DELETE") {
        const { data, error } = await admin.rpc("partner_cancel_booking", {
          p_company_id: context.companyId,
          p_external_system: context.externalSystem,
          p_external_booking_id: externalBookingId,
        });
        if (error) return jsonResponse({ error: error.message }, 400);
        await emitWebhook(
          context.companyId,
          context.externalSystem,
          "booking.cancelled",
          data as Record<string, unknown>,
        );
        return jsonResponse(data);
      }
    }

    const confirmMatch = path.match(/^\/v1\/bookings\/([^/]+)\/confirm$/);
    if (req.method === "POST" && confirmMatch) {
      const externalBookingId = decodeURIComponent(confirmMatch[1]);
      const body = (await req.json().catch(() => ({}))) as ConfirmBookingBody;

      const { data, error } = await admin.rpc("partner_confirm_booking", {
        p_company_id: context.companyId,
        p_external_system: context.externalSystem,
        p_external_booking_id: externalBookingId,
        p_external_payment_ref: body.externalPaymentRef ?? null,
      });

      if (error) return jsonResponse({ error: error.message }, 400);
      await emitWebhook(
        context.companyId,
        context.externalSystem,
        "booking.confirmed",
        data as Record<string, unknown>,
      );
      return jsonResponse(data);
    }

    return jsonResponse({ error: "Route introuvable" }, 404);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Erreur serveur";
    return jsonResponse({ error: message }, 500);
  }
});
