import Dexie, { type Table } from "dexie";
import type { CachedTripRecord, LocalSeatHold, OfflineCounterSaleRecord } from "./types.ts";

class TibusOfflineDb extends Dexie {
  counterSales!: Table<OfflineCounterSaleRecord, string>;
  cachedTrips!: Table<CachedTripRecord, string>;
  localSeatHolds!: Table<LocalSeatHold, string>;

  constructor() {
    super("tibus-offline");
    this.version(1).stores({
      counterSales: "clientMutationId, status, sellerUserId, reservationId, createdAt",
      cachedTrips: "tripId, sellerUserId, cachedAt",
      localSeatHolds: "[reservationId+seatNumber], reservationId, clientMutationId",
    });
  }
}

export const offlineDb = new TibusOfflineDb();
