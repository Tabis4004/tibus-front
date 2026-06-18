import Dexie, { type Table } from "dexie";
import type {
  CachedStationCashRecord,
  CachedTripRecord,
  LocalSeatHold,
  OfflineCounterSaleRecord,
} from "./types.ts";

class TibusOfflineDb extends Dexie {
  counterSales!: Table<OfflineCounterSaleRecord, string>;
  cachedTrips!: Table<CachedTripRecord, string>;
  localSeatHolds!: Table<LocalSeatHold, string>;
  stationCashSessions!: Table<CachedStationCashRecord, string>;

  constructor() {
    super("tibus-offline");
    this.version(1).stores({
      counterSales: "clientMutationId, status, sellerUserId, reservationId, createdAt",
      cachedTrips: "tripId, sellerUserId, cachedAt",
      localSeatHolds: "[reservationId+seatNumber], reservationId, clientMutationId",
    });
    this.version(2).stores({
      counterSales: "clientMutationId, status, sellerUserId, reservationId, createdAt",
      cachedTrips: "tripId, sellerUserId, departureGareId, cachedAt",
      localSeatHolds: "[reservationId+seatNumber], reservationId, clientMutationId",
      stationCashSessions: "sellerUserId, cachedAt",
    });
  }
}

export const offlineDb = new TibusOfflineDb();
