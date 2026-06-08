import { supabase } from "@/lib/supabase";
import { isIssuedTicket } from "@/lib/supabase/ticket-policy";
import {
  listOwnerDeparturesSupabase,
  type OwnerDeparture,
} from "@/lib/supabase/owner-trips";
import {
  getCompanyForAppUserSupabase,
  getMyCompanySupabase,
  resolveCompanyStaffCompanyId,
  resolveOwnerCompanyId,
} from "@/lib/supabase/owner-company";

export type OwnerTicketReportRow = {
  _id: string;
  _creationTime: number;
  bookingReference: string;
  passengerName: string;
  passengerPhone: string | undefined;
  status: string;
  paymentStatus: string | undefined;
  totalPrice: number;
  currency: string;
  parcelCount: number | undefined;
  parcelWeight: number | undefined;
  parcelAmount: number | undefined;
  sellerId: string | null;
  sellerName: string | null;
  tripId: string;
  routeId: string;
  busId: string;
  busName: string;
  busPlateNumber: string;
  originCity: string;
  destinationCity: string;
  departureTime: string;
  isReservation: boolean;
};

export type OwnerTicketReport = {
  tickets: OwnerTicketReportRow[];
  filters: {
    sellers: { _id: string; name: string }[];
    buses: { _id: string; name: string; plateNumber: string }[];
    routes: { routeId: string; label: string }[];
    departureCities: string[];
  };
};

export type OwnerTripReportRow = {
  _id: string;
  _creationTime: number;
  departureTime: string;
  arrivalTime: string;
  status: string;
  priceAmount: number;
  currency: string;
  totalSeats: number;
  seatsAvailable: number;
  busId: string;
  busName: string;
  busPlateNumber: string;
  routeId: string;
  originCity: string;
  destinationCity: string;
  departureStation: string;
  bookingCount: number;
  revenue: number;
  occupancyRate: number;
};

export type OwnerTripReport = {
  trips: OwnerTripReportRow[];
  filters: {
    buses: { _id: string; name: string; plateNumber: string }[];
    routes: { routeId: string; label: string }[];
    departureCities: string[];
    departureStations: string[];
  };
};

export type TripManifestRow = {
  passengerName: string;
  ticketNumber: string;
  departureStation: string;
  parcelCount: number;
  reservationStatus: "Payé" | "Réservé";
};

export type TripManifest = {
  companyName: string;
  routeLabel: string;
  departureTime: string;
  busName: string;
  busPlateNumber: string;
  departureStation: string;
  passengers: TripManifestRow[];
};

export type OwnerTravelerReportRow = {
  _id: string;
  name: string;
  phone: string | undefined;
  email: string | undefined;
  totalBookings: number;
  totalSpent: number;
  currency: string;
  lastTripDate: string | null;
  lastRoute: string | null;
};

type ReservationBusRow = {
  id: string;
  reservationId: string;
  price: number;
  isReservation: boolean;
  createdAt: string;
  paymentId: string;
  createdBy: string | null;
  passengerName: string | null;
  parcelCount: number | null;
  ticketStatus?: string | null;
};

type PaymentRow = {
  id: string;
  reference: string | null;
  phone: string | null;
  amount: number | null;
  txID: string | null;
};

type UserRow = {
  id: string;
  firstName: string | null;
  lastName: string | null;
  email: string | null;
  phone: string | null;
};

function cityFromGare(gareName: string): string {
  const parts = gareName.split("—");
  if (parts.length > 1) return parts[parts.length - 1].trim();
  return gareName.replace(/^Gare\s+/i, "").trim();
}

function deriveTicketStatus(
  isReservation: boolean,
  txID: string | null | undefined,
  departureTime: string,
) {
  if (isReservation && !txID) return "pending_payment";
  return new Date(departureTime) < new Date() ? "collected" : "confirmed";
}

function routeLabel(trip: OwnerDeparture) {
  return `${trip.origin?.name ?? "Unknown"} → ${trip.destination?.name ?? "Unknown"}`;
}

function filtersFromTickets(tickets: OwnerTicketReportRow[]): OwnerTicketReport["filters"] {
  const sellers = new Map<string, string>();
  const buses = new Map<string, { _id: string; name: string; plateNumber: string }>();
  const routes = new Map<string, string>();
  const departureCities = new Set<string>();

  for (const ticket of tickets) {
    if (ticket.sellerId && ticket.sellerName) sellers.set(ticket.sellerId, ticket.sellerName);
    if (ticket.busId) {
      buses.set(ticket.busId, {
        _id: ticket.busId,
        name: ticket.busName,
        plateNumber: ticket.busPlateNumber,
      });
    }
    routes.set(ticket.routeId, `${ticket.originCity} → ${ticket.destinationCity}`);
    if (ticket.originCity) departureCities.add(ticket.originCity);
  }

  return {
    sellers: [...sellers.entries()].map(([_id, name]) => ({ _id, name })),
    buses: [...buses.values()],
    routes: [...routes.entries()].map(([routeId, label]) => ({ routeId, label })),
    departureCities: [...departureCities].sort(),
  };
}

function filtersFromTrips(trips: OwnerTripReportRow[]): OwnerTripReport["filters"] {
  const buses = new Map<string, { _id: string; name: string; plateNumber: string }>();
  const routes = new Map<string, string>();
  const departureCities = new Set<string>();
  const departureStations = new Set<string>();

  for (const trip of trips) {
    if (trip.busId) {
      buses.set(trip.busId, {
        _id: trip.busId,
        name: trip.busName,
        plateNumber: trip.busPlateNumber,
      });
    }
    routes.set(trip.routeId, `${trip.originCity} → ${trip.destinationCity}`);
    if (trip.originCity) departureCities.add(trip.originCity);
    if (trip.departureStation) departureStations.add(trip.departureStation);
  }

  return {
    buses: [...buses.values()],
    routes: [...routes.entries()].map(([routeId, label]) => ({ routeId, label })),
    departureCities: [...departureCities].sort(),
    departureStations: [...departureStations].sort(),
  };
}

function manifestReservationStatus(
  isReservation: boolean,
  txID: string | null | undefined,
): "Payé" | "Réservé" {
  if (!isReservation || Boolean(txID)) return "Payé";
  return "Réservé";
}

function isCancelledBooking(ticketStatus: string | null | undefined): boolean {
  return ticketStatus === "cancelled";
}

async function loadIssuedBookingsForDepartures(departures: OwnerDeparture[]) {
  const reservationIds = departures.map((trip) => trip.id);
  if (!reservationIds.length) {
    return {
      bookings: [] as ReservationBusRow[],
      paymentMap: new Map<string, PaymentRow>(),
      userMap: new Map<string, UserRow>(),
    };
  }

  const { data: bookingRows, error: bookingError } = await supabase
    .from("ReservationBus")
    .select("id, reservationId, price, isReservation, createdAt, paymentId, createdBy, passengerName")
    .in("reservationId", reservationIds)
    .eq("type", "voyage")
    .order("createdAt", { ascending: false });

  if (bookingError) throw bookingError;
  const bookings = (bookingRows ?? []) as ReservationBusRow[];
  if (!bookings.length) {
    return {
      bookings: [],
      paymentMap: new Map<string, PaymentRow>(),
      userMap: new Map<string, UserRow>(),
    };
  }

  const paymentIds = [...new Set(bookings.map((booking) => booking.paymentId).filter(Boolean))];
  const { data: payments, error: paymentError } = paymentIds.length
    ? await supabase
        .from("Payment")
        .select("id, reference, phone, amount, txID")
        .in("id", paymentIds)
    : { data: [], error: null };

  if (paymentError) throw paymentError;
  const paymentMap = new Map(
    ((payments ?? []) as PaymentRow[]).map((payment) => [payment.id, payment]),
  );

  const userIds = [...new Set(bookings.map((booking) => booking.createdBy).filter(Boolean))] as string[];
  const { data: users, error: userError } = userIds.length
    ? await supabase
        .from("Users")
        .select("id, firstName, lastName, email, phone")
        .in("id", userIds)
    : { data: [], error: null };

  if (userError) throw userError;
  const userMap = new Map(((users ?? []) as UserRow[]).map((user) => [user.id, user]));

  return {
    bookings: bookings.filter((booking) => {
      const payment = paymentMap.get(booking.paymentId);
      return isIssuedTicket(booking.isReservation, payment?.txID);
    }),
    paymentMap,
    userMap,
  };
}

export async function getOwnerTicketReportSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<OwnerTicketReport> {
  const departures = await listOwnerDeparturesSupabase(appUserId, companyId);
  const tripMap = new Map(departures.map((trip) => [trip.id, trip]));
  const { bookings, paymentMap, userMap } = await loadIssuedBookingsForDepartures(departures);
  const company = await getMyCompanySupabase(appUserId, companyId);
  const currency = company?.currency ?? "XOF";

  const tickets: OwnerTicketReportRow[] = [];
  for (const booking of bookings) {
    const trip = tripMap.get(booking.reservationId);
    const payment = paymentMap.get(booking.paymentId);
    if (!trip || !payment) continue;

    const seller = booking.createdBy ? userMap.get(booking.createdBy) : undefined;
    const sellerName = seller
      ? `${seller.firstName ?? ""} ${seller.lastName ?? ""}`.trim() || seller.email
      : null;
    const passengerName =
      booking.passengerName?.trim() ||
      sellerName ||
      payment.phone ||
      "Passager";

    tickets.push({
      _id: booking.id,
      _creationTime: new Date(booking.createdAt).getTime(),
      bookingReference: payment.reference || booking.id,
      passengerName,
      passengerPhone: payment.phone ?? undefined,
      status: deriveTicketStatus(booking.isReservation, payment.txID, trip.departureTime),
      paymentStatus: payment.txID || !booking.isReservation ? "paid" : "pending",
      totalPrice: booking.price,
      currency,
      parcelCount: undefined,
      parcelWeight: undefined,
      parcelAmount: undefined,
      sellerId: booking.createdBy,
      sellerName,
      tripId: trip.id,
      routeId: trip.trajetId,
      busId: trip.bus?.id ?? "",
      busName: trip.bus?.name ?? "Bus",
      busPlateNumber: trip.bus?.plateNumber ?? "",
      originCity: cityFromGare(trip.origin?.name ?? ""),
      destinationCity: cityFromGare(trip.destination?.name ?? ""),
      departureTime: trip.departureTime,
      isReservation: booking.isReservation,
    });
  }

  return {
    tickets,
    filters: filtersFromTickets(tickets),
  };
}

export async function getOwnerTripReportSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<OwnerTripReport> {
  const departures = await listOwnerDeparturesSupabase(appUserId, companyId);
  const { bookings } = await loadIssuedBookingsForDepartures(departures);
  const bookingsByReservation = new Map<string, { count: number; revenue: number }>();

  for (const booking of bookings) {
    const current = bookingsByReservation.get(booking.reservationId) ?? {
      count: 0,
      revenue: 0,
    };
    current.count += 1;
    current.revenue += booking.price;
    bookingsByReservation.set(booking.reservationId, current);
  }

  const trips = departures.map((trip) => {
    const bookingSummary = bookingsByReservation.get(trip.id) ?? {
      count: trip.seatsBooked,
      revenue: trip.seatsBooked * trip.priceAmount,
    };

    return {
      _id: trip.id,
      _creationTime: new Date(trip.departureTime).getTime(),
      departureTime: trip.departureTime,
      arrivalTime: trip.arrivalTime,
      status: trip.status,
      priceAmount: trip.priceAmount,
      currency: trip.currency,
      totalSeats: trip.totalSeats,
      seatsAvailable: trip.seatsAvailable,
      busId: trip.bus?.id ?? "",
      busName: trip.bus?.name ?? "Bus",
      busPlateNumber: trip.bus?.plateNumber ?? "",
      routeId: trip.trajetId,
      originCity: cityFromGare(trip.origin?.name ?? ""),
      destinationCity: cityFromGare(trip.destination?.name ?? ""),
      departureStation: trip.origin?.name ?? "",
      bookingCount: bookingSummary.count,
      revenue: bookingSummary.revenue,
      occupancyRate: trip.totalSeats
        ? Math.round((bookingSummary.count / trip.totalSeats) * 100)
        : 0,
    } satisfies OwnerTripReportRow;
  });

  return {
    trips,
    filters: filtersFromTrips(trips),
  };
}

async function loadManifestBookingsForTrip(reservationId: string) {
  const { data: bookingRows, error: bookingError } = await supabase
    .from("ReservationBus")
    .select(
      "id, reservationId, price, isReservation, createdAt, paymentId, createdBy, passengerName, parcelCount, ticketStatus",
    )
    .eq("reservationId", reservationId)
    .eq("type", "voyage")
    .order("createdAt", { ascending: true });

  if (bookingError) throw bookingError;
  const bookings = ((bookingRows ?? []) as ReservationBusRow[]).filter(
    (booking) => !isCancelledBooking(booking.ticketStatus),
  );
  if (!bookings.length) {
    return {
      bookings: [] as ReservationBusRow[],
      paymentMap: new Map<string, PaymentRow>(),
      userMap: new Map<string, UserRow>(),
    };
  }

  const paymentIds = [...new Set(bookings.map((booking) => booking.paymentId).filter(Boolean))];
  const { data: payments, error: paymentError } = paymentIds.length
    ? await supabase
        .from("Payment")
        .select("id, reference, phone, amount, txID")
        .in("id", paymentIds)
    : { data: [], error: null };

  if (paymentError) throw paymentError;
  const paymentMap = new Map(
    ((payments ?? []) as PaymentRow[]).map((payment) => [payment.id, payment]),
  );

  const userIds = [...new Set(bookings.map((booking) => booking.createdBy).filter(Boolean))] as string[];
  const { data: users, error: userError } = userIds.length
    ? await supabase
        .from("Users")
        .select("id, firstName, lastName, email, phone")
        .in("id", userIds)
    : { data: [], error: null };

  if (userError) throw userError;
  const userMap = new Map(((users ?? []) as UserRow[]).map((user) => [user.id, user]));

  return { bookings, paymentMap, userMap };
}

export async function getTripManifestSupabase(
  reservationId: string,
  appUserId: string,
): Promise<TripManifest> {
  const companyId = await resolveCompanyStaffCompanyId(appUserId);
  if (!companyId) throw new Error("Compagnie introuvable");

  const departures = await listOwnerDeparturesSupabase(appUserId);
  const trip = departures.find((row) => row.id === reservationId);
  if (!trip) throw new Error("Voyage introuvable");

  const company = await getCompanyForAppUserSupabase(appUserId);
  const { bookings, paymentMap, userMap } = await loadManifestBookingsForTrip(reservationId);
  const departureStation = trip.origin?.name ?? "";

  const passengers: TripManifestRow[] = bookings.map((booking) => {
    const payment = paymentMap.get(booking.paymentId);
    const seller = booking.createdBy ? userMap.get(booking.createdBy) : undefined;
    const sellerName = seller
      ? `${seller.firstName ?? ""} ${seller.lastName ?? ""}`.trim() || seller.email
      : null;

    return {
      passengerName:
        booking.passengerName?.trim() ||
        sellerName ||
        payment?.phone ||
        "Passager",
      ticketNumber: payment?.reference || booking.id,
      departureStation,
      parcelCount: Math.max(0, Number(booking.parcelCount ?? 0) || 0),
      reservationStatus: manifestReservationStatus(
        booking.isReservation,
        payment?.txID,
      ),
    };
  });

  return {
    companyName: company?.name ?? "Compagnie",
    routeLabel: `${trip.origin?.name ?? "?"} → ${trip.destination?.name ?? "?"}`,
    departureTime: trip.departureTime,
    busName: trip.bus?.name ?? "Bus",
    busPlateNumber: trip.bus?.plateNumber ?? "",
    departureStation,
    passengers,
  };
}

export async function getOwnerTravelersSupabase(
  appUserId: string,
  companyId?: string | null,
): Promise<OwnerTravelerReportRow[]> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return [];

  const departures = await listOwnerDeparturesSupabase(appUserId, resolvedCompanyId);
  const tripMap = new Map(departures.map((trip) => [trip.id, trip]));
  const { bookings, paymentMap, userMap } = await loadIssuedBookingsForDepartures(departures);
  const company = await getMyCompanySupabase(appUserId, resolvedCompanyId);
  const currency = company?.currency ?? "XOF";
  const travelers = new Map<string, OwnerTravelerReportRow>();

  for (const booking of bookings) {
    const trip = tripMap.get(booking.reservationId);
    const payment = paymentMap.get(booking.paymentId);
    if (!trip || !payment) continue;

    const user = booking.createdBy ? userMap.get(booking.createdBy) : undefined;
    const name =
      booking.passengerName?.trim() ||
      (user ? `${user.firstName ?? ""} ${user.lastName ?? ""}`.trim() : "") ||
      payment.phone ||
      "Passager";
    const key = booking.createdBy || payment.phone || booking.passengerName || booking.id;
    const route = routeLabel(trip);
    const existing = travelers.get(key);

    if (!existing) {
      travelers.set(key, {
        _id: key,
        name,
        phone: payment.phone ?? user?.phone ?? undefined,
        email: user?.email ?? undefined,
        totalBookings: 1,
        totalSpent: booking.price,
        currency,
        lastTripDate: trip.departureTime,
        lastRoute: route,
      });
      continue;
    }

    existing.totalBookings += 1;
    existing.totalSpent += booking.price;
    if (!existing.lastTripDate || trip.departureTime > existing.lastTripDate) {
      existing.lastTripDate = trip.departureTime;
      existing.lastRoute = route;
    }
  }

  return [...travelers.values()].sort((a, b) => b.totalBookings - a.totalBookings);
}
