import { useEffect, useState } from "react";
import {
  getTripDetailSupabase,
  getOccupiedSeatsSupabase,
  type TripDetailResult,
} from "@/lib/supabase/trip-detail";

export function useSupabaseTripDetail(reservationId: string | undefined) {
  const [data, setData] = useState<TripDetailResult | null | undefined>(
    undefined,
  );

  useEffect(() => {
    if (!reservationId) {
      setData(undefined);
      return;
    }

    let cancelled = false;
    setData(undefined);

    void getTripDetailSupabase(reservationId)
      .then((trip) => {
        if (!cancelled) setData(trip);
      })
      .catch((err) => {
        console.error("[trip-detail] load failed", reservationId, err);
        if (!cancelled) setData(null);
      });

    return () => {
      cancelled = true;
    };
  }, [reservationId]);

  return data;
}

export function useSupabaseOccupiedSeats(reservationId: string | undefined) {
  const [data, setData] = useState<string[] | undefined>(undefined);

  useEffect(() => {
    if (!reservationId) {
      setData(undefined);
      return;
    }

    let cancelled = false;
    setData(undefined);

    void getOccupiedSeatsSupabase(reservationId)
      .then((seats) => {
        if (!cancelled) setData(seats);
      })
      .catch(() => {
        if (!cancelled) setData([]);
      });

    return () => {
      cancelled = true;
    };
  }, [reservationId]);

  return data;
}
