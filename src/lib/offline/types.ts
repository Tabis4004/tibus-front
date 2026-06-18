import type { CounterSaleTicket, CounterTravelerInput, SellerCounterTrip } from "@/lib/supabase/seller-counter.ts";
import type { OpenStationCash } from "@/lib/supabase/station-cash.ts";

export type OfflineOutboxStatus = "pending" | "syncing" | "synced" | "failed";

export type OfflineCounterSaleRecord = {
  clientMutationId: string;
  sellerUserId: string;
  reservationId: string;
  tripSnapshot: SellerCounterTrip;
  traveler: CounterTravelerInput;
  localTicket: CounterSaleTicket;
  status: OfflineOutboxStatus;
  attempts: number;
  lastError: string | null;
  createdAt: string;
  syncedAt: string | null;
};

export type CachedTripRecord = {
  tripId: string;
  sellerUserId: string;
  departureGareId?: string;
  payload: SellerCounterTrip;
  cachedAt: string;
};

export type CachedStationCashRecord = {
  sellerUserId: string;
  payload: OpenStationCash;
  cachedAt: string;
};

export type LocalSeatHold = {
  reservationId: string;
  seatNumber: string;
  clientMutationId: string;
  createdAt: string;
};
