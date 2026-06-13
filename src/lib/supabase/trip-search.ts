import { supabase } from "@/lib/supabase";
import { cityNameFromGareRow } from "@/lib/trip-display.ts";

export type SearchTripsParams = {
  originCity?: string;
  destinationCity?: string;
  departureDate?: string;
  companyId?: string;
  countryId?: string;
  reservationId?: string;
};

export type TripSearchResult = {
  _id: string;
  departureTime: string;
  arrivalTime: string;
  seatsAvailable: number;
  totalSeats: number;
  priceAmount: number;
  currency: string;
  originLoc: { city: string } | null;
  destLoc: { city: string } | null;
  origin: { name: string } | null;
  destination: { name: string } | null;
  company: { name: string } | null;
  bus: { busType: string; name: string; amenities?: string[] } | null;
  route: { estimatedDurationMinutes: number } | null;
};

type GareRow = {
  id: string;
  name: string;
  companyId: string;
  cityId?: string | null;
  Cities?: { name: string } | { name: string }[] | null;
};
type TrajetRow = {
  id: string;
  depart: string;
  final: string;
  capacity: number | null;
};
type ArretRow = {
  trajetId: string;
  fromGareId: string;
  toGareId: string;
  price: number;
  kilometrage: number | null;
};

function resolveTrajetArret(
  trajet: TrajetRow,
  arrets: ArretRow[],
): ArretRow | undefined {
  const forTrajet = arrets.filter((a) => a.trajetId === trajet.id);
  if (!forTrajet.length) return undefined;

  const direct = forTrajet.find(
    (a) => a.fromGareId === trajet.depart && a.toGareId === trajet.final,
  );
  if (direct) return direct;

  const fromDepart = forTrajet.filter((a) => a.fromGareId === trajet.depart);
  if (fromDepart.length === 1) return fromDepart[0];

  if (fromDepart.length > 1) {
    return fromDepart.reduce((best, current) =>
      (current.kilometrage ?? 0) > (best.kilometrage ?? 0) ? current : best,
    );
  }

  return forTrajet.reduce((best, current) =>
    (current.kilometrage ?? 0) > (best.kilometrage ?? 0) ? current : best,
  );
}
type CompanyRow = {
  id: string;
  name: string;
  countryId: string;
  isActive: boolean;
};
type CountryRow = { id: string; currency: string | null };
type BusRow = { id: string; model: string | null; capacity: number };
type ProgrammationBusRow = { trajetId: string; busId: string };

function joinedCityName(
  city: { name: string } | { name: string }[] | null | undefined,
): string | null {
  if (!city) return null;
  if (Array.isArray(city)) return city[0]?.name ?? null;
  return city.name ?? null;
}

function cityFromGare(gare: GareRow, cityNames: string[]): string {
  return cityNameFromGareRow(gare.name, joinedCityName(gare.Cities), cityNames);
}

function estimateArrivalIso(departureIso: string, kilometrage: number | null) {
  const departure = new Date(departureIso);
  const minutes =
    kilometrage && kilometrage > 0
      ? Math.round((kilometrage / 55) * 60)
      : 180;
  return new Date(departure.getTime() + minutes * 60_000).toISOString();
}

export async function searchTripsSupabase(
  params: SearchTripsParams,
): Promise<TripSearchResult[]> {
  const now = new Date().toISOString();

  let reservationsQuery = supabase
    .from("Reservations")
    .select("id, date, capacity, trajetId");

  if (params.reservationId) {
    reservationsQuery = reservationsQuery.eq("id", params.reservationId);
  } else {
    reservationsQuery = reservationsQuery
      .gt("date", now)
      .order("date", { ascending: true })
      .limit(200);
  }

  const { data: reservations, error: reservationsError } = await reservationsQuery;

  if (reservationsError) throw reservationsError;
  if (!reservations?.length) return [];

  const trajetIds = [...new Set(reservations.map((r) => r.trajetId as string))];

  const [
    { data: trajets, error: trajetsError },
    { data: arrets, error: arretsError },
    { data: progBuses, error: progBusesError },
    { data: cities, error: citiesError },
  ] = await Promise.all([
    supabase
      .from("ProgrammationTrajets")
      .select("id, depart, final, capacity")
      .in("id", trajetIds),
    supabase
      .from("ProgrammationTrajetArrets")
      .select("trajetId, fromGareId, toGareId, price, kilometrage")
      .in("trajetId", trajetIds),
    supabase
      .from("ProgrammationBus")
      .select("trajetId, busId")
      .in("trajetId", trajetIds)
      .eq("isActive", true),
    supabase.from("Cities").select("name"),
  ]);

  if (trajetsError) throw trajetsError;
  if (arretsError) throw arretsError;
  if (progBusesError) throw progBusesError;
  if (citiesError) throw citiesError;

  const cityNames = (cities ?? []).map((c) => c.name as string);
  const trajetMap = new Map(
    (trajets ?? []).map((t) => [t.id as string, t as TrajetRow]),
  );

  const gareIds = new Set<string>();
  for (const trajet of trajets ?? []) {
    gareIds.add(trajet.depart as string);
    gareIds.add(trajet.final as string);
  }

  const { data: gares, error: garesError } = await supabase
    .from("Gares")
    .select("id, name, companyId, cityId, Cities(name)")
    .in("id", [...gareIds]);

  if (garesError) throw garesError;

  const gareMap = new Map(
    (gares ?? []).map((g) => [g.id as string, g as GareRow]),
  );

  const companyIds = [...new Set((gares ?? []).map((g) => g.companyId as string))];
  const { data: companies, error: companiesError } = await supabase
    .from("Companies")
    .select("id, name, countryId, isActive")
    .in("id", companyIds);

  if (companiesError) throw companiesError;

  const companyMap = new Map(
    (companies ?? []).map((c) => [c.id as string, c as CompanyRow]),
  );

  const countryIds = [...new Set((companies ?? []).map((c) => c.countryId as string))];
  const { data: countries, error: countriesError } = await supabase
    .from("Countries")
    .select("id, currency")
    .in("id", countryIds);

  if (countriesError) throw countriesError;

  const countryMap = new Map(
    (countries ?? []).map((c) => [c.id as string, c as CountryRow]),
  );

  const busIds = [...new Set((progBuses ?? []).map((pb) => pb.busId as string))];
  let busMap = new Map<string, BusRow>();

  if (busIds.length > 0) {
    const { data: buses, error: busesError } = await supabase
      .from("Bus")
      .select("id, model, capacity")
      .in("id", busIds);

    if (busesError) throw busesError;
    busMap = new Map((buses ?? []).map((b) => [b.id as string, b as BusRow]));
  }

  const progBusMap = new Map<string, string>();
  for (const pb of progBuses ?? []) {
    progBusMap.set(pb.trajetId as string, pb.busId as string);
  }

  const arretsByTrajet = new Map<string, ArretRow[]>();
  for (const arret of arrets ?? []) {
    const row = arret as ArretRow;
    const list = arretsByTrajet.get(row.trajetId) ?? [];
    list.push(row);
    arretsByTrajet.set(row.trajetId, list);
  }

  const results: TripSearchResult[] = [];

  for (const reservation of reservations) {
    const trajet = trajetMap.get(reservation.trajetId as string);
    if (!trajet) continue;

    const originGare = gareMap.get(trajet.depart);
    const destGare = gareMap.get(trajet.final);
    if (!originGare || !destGare) continue;

    const company = companyMap.get(originGare.companyId);
    if (!company?.isActive) continue;

    if (params.companyId && company.id !== params.companyId) continue;
    if (params.countryId && company.countryId !== params.countryId) continue;

    const originCity = cityFromGare(originGare, cityNames);
    const destCity = cityFromGare(destGare, cityNames);

    if (
      params.originCity &&
      !originCity.toLowerCase().includes(params.originCity.toLowerCase())
    ) {
      continue;
    }
    if (
      params.destinationCity &&
      !destCity.toLowerCase().includes(params.destinationCity.toLowerCase())
    ) {
      continue;
    }

    const departureIso = reservation.date as string;
    if (params.departureDate) {
      const depDay = departureIso.slice(0, 10);
      if (depDay !== params.departureDate) continue;
    }

    const arret = resolveTrajetArret(trajet, arretsByTrajet.get(trajet.id) ?? []);
    if (!arret) continue;

    const busId = progBusMap.get(trajet.id);
    const bus = busId ? busMap.get(busId) : undefined;
    const totalSeats =
      bus?.capacity ?? trajet.capacity ?? (reservation.capacity as number) ?? 45;

    const country = countryMap.get(company.countryId);
    const durationMinutes =
      arret.kilometrage && arret.kilometrage > 0
        ? Math.round((arret.kilometrage / 55) * 60)
        : 180;

    results.push({
      _id: reservation.id as string,
      departureTime: departureIso,
      arrivalTime: estimateArrivalIso(departureIso, arret.kilometrage),
      seatsAvailable: totalSeats,
      totalSeats,
      priceAmount: arret.price,
      currency: country?.currency ?? "XOF",
      originLoc: { city: originCity },
      destLoc: { city: destCity },
      origin: { name: originGare.name },
      destination: { name: destGare.name },
      company: { name: company.name },
      bus: {
        busType: "Bus",
        name: bus?.model ?? "Standard",
      },
      route: { estimatedDurationMinutes: durationMinutes },
    });
  }

  const seatCounts = await Promise.all(
    results.map(async (trip) => {
      const { data, error } = await supabase.rpc("get_occupied_seats", {
        p_reservation_id: trip._id,
      });
      if (error) return [trip._id, 0] as const;
      return [trip._id, Array.isArray(data) ? data.length : 0] as const;
    }),
  );
  const bookedByReservation = new Map(seatCounts);
  for (const trip of results) {
    const booked = bookedByReservation.get(trip._id) ?? 0;
    trip.seatsAvailable = Math.max(0, trip.totalSeats - booked);
  }

  return results;
}
