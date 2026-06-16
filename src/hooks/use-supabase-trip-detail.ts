import { useEffect, useState } from "react";
import {
  getTripDetailSupabase,
  getOccupiedSeatsSupabase,
  type TripDetailResult,
} from "@/lib/supabase/trip-detail";
import { getLocalOccupiedSeats } from "@/lib/offline/counter-sale-offline.ts";
import { subscribeNetworkStatus } from "@/lib/offline/network.ts";

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

    const load = async () => {
      setData(undefined);
      const localSeats = await getLocalOccupiedSeats(reservationId);
      try {
        const remoteSeats = await getOccupiedSeatsSupabase(reservationId);
        if (!cancelled) {
          setData(Array.from(new Set([...remoteSeats, ...localSeats])));
        }
      } catch {
        if (!cancelled) {
          setData(localSeats);
        }
      }
    };

    void load();
    const unsubscribe = subscribeNetworkStatus(() => {
      void load();
    });

    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, [reservationId]);

  return data;
}
