import { useEffect, useState } from "react";
import {
  listCountriesSupabase,
  listCitiesSupabase,
  type CountryRow,
  type CityRow,
} from "@/lib/supabase/geography";
import { listActiveCompaniesSupabase, type CompanyRow } from "@/lib/supabase/companies";
import {
  searchTripsSupabase,
  type SearchTripsParams,
  type TripSearchResult,
} from "@/lib/supabase/trip-search";

export function useSupabaseCountries() {
  const [data, setData] = useState<CountryRow[] | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    void listCountriesSupabase()
      .then((rows) => {
        if (!cancelled) setData(rows);
      })
      .catch(() => {
        if (!cancelled) setData([]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  return data;
}

export function useSupabaseCities(countryId: string) {
  const [data, setData] = useState<CityRow[] | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    void listCitiesSupabase(countryId !== "all" ? countryId : undefined)
      .then((rows) => {
        if (!cancelled) setData(rows);
      })
      .catch(() => {
        if (!cancelled) setData([]);
      });
    return () => {
      cancelled = true;
    };
  }, [countryId]);

  return data;
}

export function useSupabaseActiveCompanies() {
  const [data, setData] = useState<CompanyRow[] | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    void listActiveCompaniesSupabase()
      .then((rows) => {
        if (!cancelled) setData(rows);
      })
      .catch(() => {
        if (!cancelled) setData([]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  return data;
}

export function useSupabaseSearchTrips(params: SearchTripsParams, enabled = true) {
  const [data, setData] = useState<TripSearchResult[] | undefined>(undefined);
  const paramsKey = JSON.stringify(params);

  useEffect(() => {
    if (!enabled) {
      setData(undefined);
      return;
    }

    let cancelled = false;
    setData(undefined);

    void searchTripsSupabase(params)
      .then((rows) => {
        if (!cancelled) setData(rows);
      })
      .catch(() => {
        if (!cancelled) setData([]);
      });

    return () => {
      cancelled = true;
    };
  }, [paramsKey, enabled]);

  return data;
}
