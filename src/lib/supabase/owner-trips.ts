import { supabase } from "@/lib/supabase";
import { isIssuedTicket } from "@/lib/supabase/ticket-policy";
import { cityNameFromGareRow } from "@/lib/trip-display.ts";
import {
  resolveCompanyStaffCompanyId,
  resolveOwnerCompanyId,
} from "@/lib/supabase/owner-company";

export type OwnerRouteOption = {
  id: string;
  originName: string;
  destName: string;
  originCity: string;
  destCity: string;
  price: number;
  currency: string;
  kilometrage: number | null;
};

export type OwnerStationOption = {
  id: string;
  name: string;
  city: string;
  country: string;
};

export type OwnerBusOption = {
  id: string;
  name: string;
  plateNumber: string;
  capacity: number;
};

export type OwnerDeparture = {
  id: string;
  trajetId: string;
  departureTime: string;
  arrivalTime: string;
  priceAmount: number;
  currency: string;
  totalSeats: number;
  seatsAvailable: number;
  seatsBooked: number;
  status: "scheduled" | "active" | "completed";
  origin: { name: string; city: string } | null;
  destination: { name: string; city: string } | null;
  bus: { id: string; name: string; plateNumber: string } | null;
};

function joinedCityName(
  city: { name: string } | { name: string }[] | null | undefined,
): string | null {
  if (!city) return null;
  if (Array.isArray(city)) return city[0]?.name ?? null;
  return city.name ?? null;
}

type GareWithCityRow = {
  id: string;
  name: string;
  cityId?: string | null;
  Cities?: { name: string } | { name: string }[] | null;
};

function resolveGareCity(gare: GareWithCityRow, cityNames: string[] = []): string {
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

function deriveStatus(dateIso: string): OwnerDeparture["status"] {
  const dep = new Date(dateIso).getTime();
  const now = Date.now();
  if (dep < now - 3 * 60 * 60_000) return "completed";
  if (dep <= now) return "active";
  return "scheduled";
}

async function countIssuedSeats(reservationId: string): Promise<number> {
  const { data: rows, error } = await supabase
    .from("ReservationBus")
    .select("isReservation, paymentId")
    .eq("reservationId", reservationId)
    .eq("type", "voyage");

  if (error) throw error;
  if (!rows?.length) return 0;

  const paymentIds = rows.map((r) => r.paymentId as string);
  const { data: payments, error: payError } = await supabase
    .from("Payment")
    .select("id, txID")
    .in("id", paymentIds);

  if (payError) throw payError;

  const paymentTx = new Map(
    (payments ?? []).map((p) => [p.id as string, p.txID as string | null]),
  );

  return rows.filter((r) => {
    const txID = paymentTx.get(r.paymentId as string);
    return isIssuedTicket(r.isReservation as boolean, txID);
  }).length;
}

async function companyTrajetIds(companyId: string): Promise<string[]> {
  const { data: gares, error: garesError } = await supabase
    .from("Gares")
    .select("id")
    .eq("companyId", companyId);

  if (garesError) throw garesError;
  const gareIds = (gares ?? []).map((g) => g.id as string);
  if (!gareIds.length) return [];

  const { data: trajets, error: trajetsError } = await supabase
    .from("ProgrammationTrajets")
    .select("id")
    .in("depart", gareIds);

  if (trajetsError) throw trajetsError;
  return (trajets ?? []).map((t) => t.id as string);
}

export async function listOwnerRoutesSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<OwnerRouteOption[]> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return [];

  const trajetIds = await companyTrajetIds(resolvedCompanyId);
  if (!trajetIds.length) return [];

  const { data: trajets, error: trajetsError } = await supabase
    .from("ProgrammationTrajets")
    .select("id, depart, final")
    .in("id", trajetIds);

  if (trajetsError) throw trajetsError;

  const { data: arrets, error: arretsError } = await supabase
    .from("ProgrammationTrajetArrets")
    .select("trajetId, fromGareId, toGareId, price, kilometrage")
    .in("trajetId", trajetIds);

  if (arretsError) throw arretsError;

  const gareIds = new Set<string>();
  for (const t of trajets ?? []) {
    gareIds.add(t.depart as string);
    gareIds.add(t.final as string);
  }

  const { data: gares, error: garesError } = await supabase
    .from("Gares")
    .select("id, name, cityId, Cities(name)")
    .in("id", [...gareIds]);

  if (garesError) throw garesError;

  const { data: cities, error: citiesError } = await supabase.from("Cities").select("name");
  if (citiesError) throw citiesError;
  const cityNames = (cities ?? []).map((c) => c.name as string);

  const gareMap = new Map(
    (gares ?? []).map((g) => [g.id as string, g as GareWithCityRow]),
  );

  const { data: company, error: companyError } = await supabase
    .from("Companies")
    .select("countryId")
    .eq("id", resolvedCompanyId)
    .single();

  if (companyError) throw companyError;

  const { data: country, error: countryError } = await supabase
    .from("Countries")
    .select("currency")
    .eq("id", company.countryId as string)
    .maybeSingle();

  if (countryError) throw countryError;

  const currency = (country?.currency as string) ?? "XOF";
  const routes: OwnerRouteOption[] = [];

  for (const trajet of trajets ?? []) {
    const arret = (arrets ?? []).find(
      (a) =>
        a.trajetId === trajet.id &&
        a.fromGareId === trajet.depart &&
        a.toGareId === trajet.final,
    );
    if (!arret) continue;

    const originGare = gareMap.get(trajet.depart as string);
    const destGare = gareMap.get(trajet.final as string);
    if (!originGare || !destGare) continue;

    const originName = originGare.name;
    const destName = destGare.name;

    routes.push({
      id: trajet.id as string,
      originName,
      destName,
      originCity: resolveGareCity(originGare, cityNames),
      destCity: resolveGareCity(destGare, cityNames),
      price: arret.price as number,
      currency,
      kilometrage: (arret.kilometrage as number | null) ?? null,
    });
  }

  return routes.sort((a, b) => a.originCity.localeCompare(b.originCity));
}

export async function listOwnerRouteStationsSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<OwnerStationOption[]> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return [];

  const { data, error } = await supabase
    .from("Gares")
    .select("id, name, cityId, Cities(name)")
    .eq("companyId", resolvedCompanyId)
    .order("name");

  if (error) throw error;

  const { data: cities, error: citiesError } = await supabase.from("Cities").select("name");
  if (citiesError) throw citiesError;
  const cityNames = (cities ?? []).map((c) => c.name as string);

  return (data ?? []).map((gare) => ({
    id: gare.id as string,
    name: gare.name as string,
    city: resolveGareCity(gare as GareWithCityRow, cityNames),
    country: "",
  }));
}

export async function createOwnerRouteSupabase(input: {
  originStationId: string;
  destinationStationId: string;
  price: number;
  kilometrage?: number;
  capacity?: number;
}): Promise<string> {
  const { data, error } = await supabase.rpc("create_owner_route", {
    p_depart: input.originStationId,
    p_final: input.destinationStationId,
    p_price: input.price,
    p_kilometrage: input.kilometrage ?? null,
    p_capacity: input.capacity ?? null,
  });

  if (error) throw error;
  return data as string;
}

export async function listOwnerBusesSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<OwnerBusOption[]> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return [];

  const { data, error } = await supabase
    .from("Bus")
    .select("id, model, registrationNumber, capacity")
    .eq("companyId", resolvedCompanyId)
    .eq("isActive", true)
    .order("registrationNumber");

  if (error) throw error;

  return (data ?? []).map((b) => ({
    id: b.id as string,
    name: (b.model as string) || "Bus",
    plateNumber: b.registrationNumber as string,
    capacity: b.capacity as number,
  }));
}

export async function listOwnerDeparturesSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<OwnerDeparture[]> {
  const resolvedCompanyId =
    (await resolveOwnerCompanyId(appUserId, companyId))
    ?? (await resolveCompanyStaffCompanyId(appUserId));
  if (!resolvedCompanyId) return [];

  const trajetIds = await companyTrajetIds(resolvedCompanyId);
  if (!trajetIds.length) return [];

  const { data: reservations, error: resError } = await supabase
    .from("Reservations")
    .select("id, date, capacity, trajetId")
    .in("trajetId", trajetIds)
    .order("date", { ascending: false });

  if (resError) throw resError;
  if (!reservations?.length) return [];

  const { data: trajets, error: trajetsError } = await supabase
    .from("ProgrammationTrajets")
    .select("id, depart, final, capacity")
    .in("id", trajetIds);

  if (trajetsError) throw trajetsError;

  const { data: arrets, error: arretsError } = await supabase
    .from("ProgrammationTrajetArrets")
    .select("trajetId, fromGareId, toGareId, price, kilometrage")
    .in("trajetId", trajetIds);

  if (arretsError) throw arretsError;

  const { data: progBuses, error: pbError } = await supabase
    .from("ProgrammationBus")
    .select("trajetId, busId")
    .in("trajetId", trajetIds)
    .eq("isActive", true);

  if (pbError) throw pbError;

  const gareIds = new Set<string>();
  for (const t of trajets ?? []) {
    gareIds.add(t.depart as string);
    gareIds.add(t.final as string);
  }

  const { data: gares, error: garesError } = await supabase
    .from("Gares")
    .select("id, name, cityId, Cities(name)")
    .in("id", [...gareIds]);

  if (garesError) throw garesError;

  const { data: cities, error: citiesError } = await supabase.from("Cities").select("name");
  if (citiesError) throw citiesError;
  const cityNames = (cities ?? []).map((c) => c.name as string);

  const gareMap = new Map(
    (gares ?? []).map((g) => [g.id as string, g as GareWithCityRow]),
  );

  const busIds = [...new Set((progBuses ?? []).map((pb) => pb.busId as string))];
  const busMap = new Map<string, { name: string; plateNumber: string; capacity: number }>();

  if (busIds.length > 0) {
    const { data: buses, error: busesError } = await supabase
      .from("Bus")
      .select("id, model, registrationNumber, capacity")
      .in("id", busIds);

    if (busesError) throw busesError;
    for (const b of buses ?? []) {
      busMap.set(b.id as string, {
        name: (b.model as string) || "Bus",
        plateNumber: b.registrationNumber as string,
        capacity: b.capacity as number,
      });
    }
  }

  const progBusMap = new Map<string, string>();
  for (const pb of progBuses ?? []) {
    progBusMap.set(pb.trajetId as string, pb.busId as string);
  }

  const { data: company, error: companyError } = await supabase
    .from("Companies")
    .select("countryId")
    .eq("id", resolvedCompanyId)
    .single();

  if (companyError) throw companyError;

  const { data: country, error: countryError } = await supabase
    .from("Countries")
    .select("currency")
    .eq("id", company.countryId as string)
    .maybeSingle();

  if (countryError) throw countryError;

  const currency = (country?.currency as string) ?? "XOF";
  const trajetMap = new Map((trajets ?? []).map((t) => [t.id as string, t]));

  const reservationIds = reservations.map((r) => r.id as string);
  const { data: allBookings, error: allBookingsError } = await supabase
    .from("ReservationBus")
    .select("reservationId, isReservation, paymentId")
    .in("reservationId", reservationIds)
    .eq("type", "voyage");

  if (allBookingsError) throw allBookingsError;

  const paymentIds = [
    ...new Set((allBookings ?? []).map((b) => b.paymentId as string)),
  ];
  const paymentTx = new Map<string, string | null>();
  if (paymentIds.length > 0) {
    const { data: payments, error: payError } = await supabase
      .from("Payment")
      .select("id, txID")
      .in("id", paymentIds);
    if (payError) throw payError;
    for (const p of payments ?? []) {
      paymentTx.set(p.id as string, p.txID as string | null);
    }
  }

  const bookedCount = new Map<string, number>();
  for (const booking of allBookings ?? []) {
    const txID = paymentTx.get(booking.paymentId as string);
    if (!isIssuedTicket(booking.isReservation as boolean, txID)) continue;
    const id = booking.reservationId as string;
    bookedCount.set(id, (bookedCount.get(id) ?? 0) + 1);
  }

  const results: OwnerDeparture[] = [];

  for (const reservation of reservations) {
    const trajet = trajetMap.get(reservation.trajetId as string);
    if (!trajet) continue;

    const arret = (arrets ?? []).find(
      (a) =>
        a.trajetId === trajet.id &&
        a.fromGareId === trajet.depart &&
        a.toGareId === trajet.final,
    );
    if (!arret) continue;

    const booked = bookedCount.get(reservation.id as string) ?? 0;
    const busId = progBusMap.get(trajet.id as string);
    const bus = busId ? busMap.get(busId) : undefined;
    const totalSeats =
      (reservation.capacity as number) ??
      bus?.capacity ??
      (trajet.capacity as number) ??
      45;

    const departureIso = reservation.date as string;

    const originGare = gareMap.get(trajet.depart as string);
    const destGare = gareMap.get(trajet.final as string);

    results.push({
      id: reservation.id as string,
      trajetId: trajet.id as string,
      departureTime: departureIso,
      arrivalTime: estimateArrivalIso(
        departureIso,
        (arret.kilometrage as number | null) ?? null,
      ),
      priceAmount: arret.price as number,
      currency,
      totalSeats,
      seatsBooked: booked,
      seatsAvailable: Math.max(0, totalSeats - booked),
      status: deriveStatus(departureIso),
      origin: originGare
        ? { name: originGare.name, city: resolveGareCity(originGare, cityNames) }
        : null,
      destination: destGare
        ? { name: destGare.name, city: resolveGareCity(destGare, cityNames) }
        : null,
      bus: bus && busId
        ? { id: busId, name: bus.name, plateNumber: bus.plateNumber }
        : null,
    });
  }

  return results;
}

export async function createOwnerDepartureSupabase(input: {
  appUserId: string;
  companyId?: string | null;
  trajetId: string;
  busId: string;
  departureIso: string;
  capacity: number;
}): Promise<string> {
  const companyId = await resolveOwnerCompanyId(input.appUserId, input.companyId);
  if (!companyId) throw new Error("Compagnie introuvable");

  const trajetIds = await companyTrajetIds(companyId);
  if (!trajetIds.includes(input.trajetId)) {
    throw new Error("Trajet non autorisé");
  }

  const { data: bus, error: busError } = await supabase
    .from("Bus")
    .select("id")
    .eq("id", input.busId)
    .eq("companyId", companyId)
    .maybeSingle();

  if (busError) throw busError;
  if (!bus) throw new Error("Bus introuvable");

  const { data: existingLink, error: linkReadError } = await supabase
    .from("ProgrammationBus")
    .select("id")
    .eq("trajetId", input.trajetId)
    .eq("busId", input.busId)
    .maybeSingle();

  if (linkReadError) throw linkReadError;

  if (!existingLink) {
    const { error: linkError } = await supabase.from("ProgrammationBus").insert({
      trajetId: input.trajetId,
      busId: input.busId,
      isActive: true,
    });
    if (linkError) throw linkError;
  }

  const { data, error } = await supabase
    .from("Reservations")
    .insert({
      trajetId: input.trajetId,
      date: input.departureIso,
      capacity: input.capacity,
    })
    .select("id")
    .single();

  if (error) throw error;
  return data.id as string;
}

export async function updateOwnerDepartureSupabase(input: {
  appUserId: string;
  companyId?: string | null;
  reservationId: string;
  departureIso: string;
  capacity: number;
  busId?: string;
  trajetId?: string;
}): Promise<void> {
  const companyId = await resolveOwnerCompanyId(input.appUserId, input.companyId);
  if (!companyId) throw new Error("Compagnie introuvable");

  const booked = await countIssuedSeats(input.reservationId);
  if (booked > 0) {
    throw new Error("Impossible de modifier un départ avec des billets payés");
  }

  const { error } = await supabase
    .from("Reservations")
    .update({
      date: input.departureIso,
      capacity: input.capacity,
      ...(input.trajetId ? { trajetId: input.trajetId } : {}),
    })
    .eq("id", input.reservationId);

  if (error) throw error;

  if (input.busId && input.trajetId) {
    const { data: existingLink } = await supabase
      .from("ProgrammationBus")
      .select("id")
      .eq("trajetId", input.trajetId)
      .eq("busId", input.busId)
      .maybeSingle();

    if (!existingLink) {
      const { error: linkError } = await supabase.from("ProgrammationBus").insert({
        trajetId: input.trajetId,
        busId: input.busId,
        isActive: true,
      });
      if (linkError) throw linkError;
    }
  }
}

export async function deleteOwnerDepartureSupabase(
  appUserId: string,
  reservationId: string,
  companyId?: string | null,
): Promise<void> {
  const booked = await countIssuedSeats(reservationId);
  if (booked > 0) {
    throw new Error("Impossible de supprimer un départ avec des billets payés");
  }

  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) throw new Error("Compagnie introuvable");

  const { error } = await supabase
    .from("Reservations")
    .delete()
    .eq("id", reservationId);

  if (error) throw error;
}
