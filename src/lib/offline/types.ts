import type { CounterSaleTicket, CounterTravelerInput, SellerCounterTrip } from "@/lib/supabase/seller-counter.ts";

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
  payload: SellerCounterTrip;
  cachedAt: string;
};

export type LocalSeatHold = {
  reservationId: string;
  seatNumber: string;
  clientMutationId: string;
  createdAt: string;
};
