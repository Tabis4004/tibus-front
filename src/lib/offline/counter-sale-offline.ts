import { randomUUID } from "@/lib/random-id.ts";
import { isBrowserOnline } from "@/lib/offline/network.ts";
import { offlineDb } from "@/lib/offline/db.ts";
import type { OfflineCounterSaleRecord } from "@/lib/offline/types.ts";
import {
  sellCounterTicketSupabase,
  type CounterSaleTicket,
  type CounterTravelerInput,
  type SellerCounterTrip,
} from "@/lib/supabase/seller-counter.ts";
import {
  getOpenStationCashSupabase,
  type OpenStationCash,
} from "@/lib/supabase/station-cash.ts";

export type CounterSaleResult = CounterSaleTicket & {
  offline?: boolean;
  clientMutationId?: string;
  pendingSync?: boolean;
};

function buildLocalReference(): string {
  const suffix = randomUUID().replace(/-/g, "").slice(0, 8).toUpperCase();
  return `OFF-${suffix}`;
}

function estimateTicketTotal(trip: SellerCounterTrip, traveler: CounterTravelerInput): number {
  const parcel = traveler.parcelAmount ?? 0;
  return Math.round((trip.priceAmount + parcel) * 100) / 100;
}

export function buildOfflineCounterTicket(input: {
  clientMutationId: string;
  trip: SellerCounterTrip;
  traveler: CounterTravelerInput;
}): CounterSaleTicket {
  const { clientMutationId, trip, traveler } = input;
  return {
    bookingId: `offline:${clientMutationId}`,
    reference: buildLocalReference(),
    verifyToken: null,
    totalPrice: estimateTicketTotal(trip, traveler),
    currency: trip.currency ?? "XOF",
    passengerName: traveler.passengerName.trim(),
    passengerPhone: traveler.passengerPhone?.trim() || undefined,
    seatNumber: traveler.seatNumber?.trim() || undefined,
    parcelCount: traveler.parcelCount ?? 0,
    parcelWeight: traveler.parcelWeight ?? 0,
    parcelAmount: traveler.parcelAmount ?? 0,
  };
}

async function reserveLocalSeat(reservationId: string, seatNumber: string, clientMutationId: string) {
  if (!seatNumber.trim()) return;
  await offlineDb.localSeatHolds.put({
    reservationId,
    seatNumber: seatNumber.trim(),
    clientMutationId,
    createdAt: new Date().toISOString(),
  });
}

export async function getLocalOccupiedSeats(reservationId: string): Promise<string[]> {
  const rows = await offlineDb.localSeatHolds.where("reservationId").equals(reservationId).toArray();
  return rows.map((row) => row.seatNumber);
}

export async function cacheStationCashOffline(sellerUserId: string, cash: OpenStationCash) {
  await offlineDb.stationCashSessions.put({
    sellerUserId,
    payload: cash,
    cachedAt: new Date().toISOString(),
  });
}

export async function getCachedStationCashOffline(
  sellerUserId: string,
): Promise<OpenStationCash | null> {
  const row = await offlineDb.stationCashSessions.get(sellerUserId);
  return row?.payload ?? null;
}

export async function resolveOpenStationCashForSeller(
  sellerUserId: string,
): Promise<OpenStationCash> {
  if (isBrowserOnline()) {
    try {
      const cash = await getOpenStationCashSupabase();
      if (cash.open) {
        await cacheStationCashOffline(sellerUserId, cash);
      }
      return cash;
    } catch {
      return (await getCachedStationCashOffline(sellerUserId)) ?? { open: false };
    }
  }
  return (await getCachedStationCashOffline(sellerUserId)) ?? { open: false };
}

export async function cacheSellerTripsOffline(
  sellerUserId: string,
  departureGareId: string,
  trips: SellerCounterTrip[],
) {
  const cachedAt = new Date().toISOString();
  await offlineDb.transaction("rw", offlineDb.cachedTrips, async () => {
    const stale = await offlineDb.cachedTrips
      .where("sellerUserId")
      .equals(sellerUserId)
      .filter((row) => row.departureGareId === departureGareId)
      .toArray();
    if (stale.length) {
      await offlineDb.cachedTrips.bulkDelete(stale.map((row) => row.tripId));
    }
    await offlineDb.cachedTrips.bulkPut(
      trips.map((trip) => ({
        tripId: trip._id,
        sellerUserId,
        departureGareId,
        payload: trip,
        cachedAt,
      })),
    );
  });
}

export async function listCachedSellerTrips(
  sellerUserId: string,
  departureGareId?: string,
): Promise<SellerCounterTrip[]> {
  const rows = await offlineDb.cachedTrips.where("sellerUserId").equals(sellerUserId).toArray();
  if (!departureGareId) {
    return rows.map((row) => row.payload);
  }
  const forGare = rows.filter((row) => row.departureGareId === departureGareId);
  if (forGare.length > 0) {
    return forGare.map((row) => row.payload);
  }
  return rows.filter((row) => !row.departureGareId).map((row) => row.payload);
}

export async function countPendingCounterSales(): Promise<number> {
  return offlineDb.counterSales.where("status").anyOf(["pending", "failed", "syncing"]).count();
}

export async function listPendingCounterSales(): Promise<OfflineCounterSaleRecord[]> {
  return offlineDb.counterSales
    .where("status")
    .anyOf(["pending", "failed", "syncing"])
    .sortBy("createdAt");
}

async function persistOfflineSale(input: {
  sellerUserId: string;
  reservationId: string;
  trip: SellerCounterTrip;
  traveler: CounterTravelerInput;
  clientMutationId: string;
  localTicket: CounterSaleTicket;
}): Promise<OfflineCounterSaleRecord> {
  const record: OfflineCounterSaleRecord = {
    clientMutationId: input.clientMutationId,
    sellerUserId: input.sellerUserId,
    reservationId: input.reservationId,
    tripSnapshot: input.trip,
    traveler: input.traveler,
    localTicket: input.localTicket,
    status: "pending",
    attempts: 0,
    lastError: null,
    createdAt: new Date().toISOString(),
    syncedAt: null,
  };
  await offlineDb.counterSales.put(record);
  await reserveLocalSeat(input.reservationId, input.traveler.seatNumber ?? "", input.clientMutationId);
  return record;
}

export async function sellCounterTicketWithOffline(input: {
  sellerUserId: string;
  reservationId: string;
  trip: SellerCounterTrip;
  traveler: CounterTravelerInput;
  forceOffline?: boolean;
}): Promise<CounterSaleResult> {
  const clientMutationId = randomUUID();
  const traveler = {
    ...input.traveler,
    passengerName: input.traveler.passengerName.trim(),
  };

  if (!input.forceOffline && isBrowserOnline()) {
    try {
      const ticket = await sellCounterTicketSupabase({
        reservationId: input.reservationId,
        traveler,
        clientMutationId,
      });
      return { ...ticket, offline: false, clientMutationId };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const transient =
        /failed to fetch|network|timeout|offline|load failed|fetch/i.test(message) ||
        !isBrowserOnline();
      if (!transient) throw error;
    }
  }

  const localTicket = buildOfflineCounterTicket({
    clientMutationId,
    trip: input.trip,
    traveler,
  });
  await persistOfflineSale({
    sellerUserId: input.sellerUserId,
    reservationId: input.reservationId,
    trip: input.trip,
    traveler,
    clientMutationId,
    localTicket,
  });

  return {
    ...localTicket,
    offline: true,
    pendingSync: true,
    clientMutationId,
  };
}

export async function syncPendingCounterSales(): Promise<{
  synced: number;
  failed: number;
  remaining: number;
}> {
  if (!isBrowserOnline()) {
    const remaining = await countPendingCounterSales();
    return { synced: 0, failed: 0, remaining };
  }

  const pending = await listPendingCounterSales();
  let synced = 0;
  let failed = 0;

  for (const record of pending) {
    await offlineDb.counterSales.update(record.clientMutationId, {
      status: "syncing",
      attempts: record.attempts + 1,
    });

    try {
      const ticket = await sellCounterTicketSupabase({
        reservationId: record.reservationId,
        traveler: record.traveler,
        clientMutationId: record.clientMutationId,
      });
      await offlineDb.counterSales.update(record.clientMutationId, {
        status: "synced",
        localTicket: ticket,
        lastError: null,
        syncedAt: new Date().toISOString(),
      });
      synced += 1;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await offlineDb.counterSales.update(record.clientMutationId, {
        status: "failed",
        lastError: message,
      });
      failed += 1;
    }
  }

  const remaining = await countPendingCounterSales();
  return { synced, failed, remaining };
}
