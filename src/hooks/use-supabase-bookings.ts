import { useCallback, useEffect, useState } from "react";
import {
  getTravelerBookingSupabase,
  listMyBookingsSupabase,
  type TravelerBooking,
} from "@/lib/supabase/bookings";

export function useSupabaseMyBookings(appUserId: string | null) {
  const [data, setData] = useState<TravelerBooking[] | undefined>(undefined);

  const refresh = useCallback(() => {
    if (!appUserId) {
      setData([]);
      return;
    }

    setData(undefined);
    void listMyBookingsSupabase(appUserId)
      .then((rows) => setData(rows))
      .catch(() => setData([]));
  }, [appUserId]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return { bookings: data, refresh };
}

export function useSupabaseTravelerBooking(
  bookingId: string | undefined,
  appUserId: string | null,
) {
  const [data, setData] = useState<TravelerBooking | null | undefined>(
    undefined,
  );

  useEffect(() => {
    if (!bookingId || !appUserId) {
      setData(undefined);
      return;
    }

    let cancelled = false;
    setData(undefined);

    void getTravelerBookingSupabase(bookingId, appUserId)
      .then((row) => {
        if (!cancelled) setData(row);
      })
      .catch(() => {
        if (!cancelled) setData(null);
      });

    return () => {
      cancelled = true;
    };
  }, [bookingId, appUserId]);

  return data;
}
