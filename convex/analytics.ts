import { query } from "./_generated/server";
import type { QueryCtx } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";
import { resolveStationLocation } from "./stationHelpers.ts";

async function getOwnerCompanyForAnalytics(ctx: QueryCtx) {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });
  const user = await ctx.db
    .query("users")
    .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
    .unique();
  if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });
  if (user.role !== "owner" && user.role !== "superadmin")
    throw new ConvexError({ message: "Owners only", code: "FORBIDDEN" });
  const company = await ctx.db
    .query("companies")
    .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
    .first();
  if (!company) throw new ConvexError({ message: "No company found", code: "NOT_FOUND" });
  return { user, company };
}

// ─── KPI Stats ───────────────────────────────────────────────────────────────
export const getKPIs = query({
  args: {},
  handler: async (ctx) => {
    const { company } = await getOwnerCompanyForAnalytics(ctx);

    // Get all trips for the company
    const trips = await ctx.db
      .query("trips")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    const now = new Date().toISOString();
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const todayEnd = new Date();
    todayEnd.setHours(23, 59, 59, 999);
    const todayStartISO = todayStart.toISOString();
    const todayEndISO = todayEnd.toISOString();

    // Trip counts
    const upcomingTrips = trips.filter((t) => t.departureTime > now && t.status === "scheduled").length;
    const todayTrips = trips.filter(
      (t) => t.departureTime >= todayStartISO && t.departureTime <= todayEndISO
    ).length;
    const completedTrips = trips.filter((t) => t.status === "completed").length;
    const totalTrips = trips.length;

    // Get all bookings across all trips
    let totalBookings = 0;
    let confirmedBookings = 0;
    let totalRevenue = 0;
    let todayRevenue = 0;
    let currency = company.planId ?? "XAF";
    const travelerIds = new Set<string>();

    for (const trip of trips) {
      const bookings = await ctx.db
        .query("bookings")
        .withIndex("by_trip", (q) => q.eq("tripId", trip._id))
        .collect();

      for (const b of bookings) {
        totalBookings++;
        if (b.status === "confirmed" || b.status === "collected") {
          confirmedBookings++;
          totalRevenue += b.totalPrice;
          travelerIds.add(b.travelerId);
          currency = b.currency;

          // Check if booking was today
          const bookingDate = new Date(b._creationTime);
          if (bookingDate >= todayStart && bookingDate <= todayEnd) {
            todayRevenue += b.totalPrice;
          }
        }
        if (b.status === "cancelled") continue;
      }
    }

    // Sellers count
    const sellers = await ctx.db
      .query("users")
      .withIndex("by_role", (q) => q.eq("role", "seller"))
      .collect();
    const companySellers = sellers.filter((s) => s.companyId === company._id).length;

    // Buses count
    const buses = await ctx.db
      .query("buses")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    return {
      totalBookings,
      confirmedBookings,
      totalRevenue,
      todayRevenue,
      currency,
      totalTrips,
      upcomingTrips,
      todayTrips,
      completedTrips,
      totalTravelers: travelerIds.size,
      totalSellers: companySellers,
      totalBuses: buses.filter((b) => b.isActive).length,
    };
  },
});

// ─── Revenue chart data (last 30 days) ──────────────────────────────────────
export const getRevenueChart = query({
  args: {},
  handler: async (ctx) => {
    const { company } = await getOwnerCompanyForAnalytics(ctx);

    const trips = await ctx.db
      .query("trips")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    // Collect daily revenue for last 30 days
    const now = new Date();
    const days: { date: string; revenue: number; tickets: number }[] = [];

    for (let i = 29; i >= 0; i--) {
      const day = new Date(now);
      day.setDate(day.getDate() - i);
      const dayStart = new Date(day);
      dayStart.setHours(0, 0, 0, 0);
      const dayEnd = new Date(day);
      dayEnd.setHours(23, 59, 59, 999);

      days.push({
        date: day.toISOString().split("T")[0],
        revenue: 0,
        tickets: 0,
      });
    }

    for (const trip of trips) {
      const bookings = await ctx.db
        .query("bookings")
        .withIndex("by_trip", (q) => q.eq("tripId", trip._id))
        .collect();

      for (const b of bookings) {
        if (b.status === "cancelled") continue;
        const bookingDate = new Date(b._creationTime).toISOString().split("T")[0];
        const dayEntry = days.find((d) => d.date === bookingDate);
        if (dayEntry) {
          dayEntry.revenue += b.totalPrice;
          dayEntry.tickets += 1;
        }
      }
    }

    return days;
  },
});

// ─── Recent bookings for quick overview ─────────────────────────────────────
export const getRecentBookings = query({
  args: {},
  handler: async (ctx) => {
    const { company } = await getOwnerCompanyForAnalytics(ctx);

    const trips = await ctx.db
      .query("trips")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    type BookingEntry = {
      _id: string;
      _creationTime: number;
      passengerName: string;
      passengerPhone: string | undefined;
      status: string;
      totalPrice: number;
      currency: string;
      bookingReference: string;
      sellerName: string | null;
      originCity: string;
      destinationCity: string;
      departureTime: string;
      busName: string;
    };

    const allBookings: BookingEntry[] = [];

    for (const trip of trips) {
      const bookings = await ctx.db
        .query("bookings")
        .withIndex("by_trip", (q) => q.eq("tripId", trip._id))
        .order("desc")
        .take(20);

      const route = await ctx.db.get(trip.routeId);
      const bus = await ctx.db.get(trip.busId);
      const origin = route ? await ctx.db.get(route.originStationId) : null;
      const destination = route ? await ctx.db.get(route.destinationStationId) : null;
      const originLoc = await resolveStationLocation(ctx, origin);
      const destLoc = await resolveStationLocation(ctx, destination);

      for (const b of bookings) {
        let sellerName: string | null = null;
        if (b.soldBySellerId) {
          const seller = await ctx.db.get(b.soldBySellerId);
          sellerName = seller?.name ?? null;
        }

        allBookings.push({
          _id: b._id,
          _creationTime: b._creationTime,
          passengerName: b.passengerName,
          passengerPhone: b.passengerPhone,
          status: b.status,
          totalPrice: b.totalPrice,
          currency: b.currency,
          bookingReference: b.bookingReference,
          sellerName,
          originCity: originLoc?.city ?? origin?.name ?? "—",
          destinationCity: destLoc?.city ?? destination?.name ?? "—",
          departureTime: trip.departureTime,
          busName: bus?.name ?? "—",
        });
      }
    }

    // Sort by creation time desc and take most recent 10
    allBookings.sort((a, b) => b._creationTime - a._creationTime);
    return allBookings.slice(0, 10);
  },
});

// ─── Trip Report (all trips with enriched data) ─────────────────────────────
export const getTripReport = query({
  args: {},
  handler: async (ctx) => {
    const { company } = await getOwnerCompanyForAnalytics(ctx);

    const trips = await ctx.db
      .query("trips")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    // Get all buses for this company
    const buses = await ctx.db
      .query("buses")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    type TripRow = {
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
      bookingCount: number;
      revenue: number;
      occupancyRate: number;
    };

    const tripRows: TripRow[] = [];

    for (const trip of trips) {
      const route = await ctx.db.get(trip.routeId);
      const bus = buses.find((b) => b._id === trip.busId);
      const origin = route ? await ctx.db.get(route.originStationId) : null;
      const destination = route ? await ctx.db.get(route.destinationStationId) : null;
      const originLoc = await resolveStationLocation(ctx, origin);
      const destLoc = await resolveStationLocation(ctx, destination);

      const bookings = await ctx.db
        .query("bookings")
        .withIndex("by_trip", (q) => q.eq("tripId", trip._id))
        .collect();

      const confirmedBookings = bookings.filter(
        (b) => b.status === "confirmed" || b.status === "collected"
      );
      const revenue = confirmedBookings.reduce((sum, b) => sum + b.totalPrice, 0);
      const bookedSeats = bookings.filter((b) => b.status !== "cancelled").length;
      const occupancyRate = trip.totalSeats > 0 ? Math.round((bookedSeats / trip.totalSeats) * 100) : 0;

      tripRows.push({
        _id: trip._id,
        _creationTime: trip._creationTime,
        departureTime: trip.departureTime,
        arrivalTime: trip.arrivalTime,
        status: trip.status,
        priceAmount: trip.priceAmount,
        currency: trip.currency,
        totalSeats: trip.totalSeats,
        seatsAvailable: trip.seatsAvailable,
        busId: trip.busId,
        busName: bus?.name ?? "—",
        busPlateNumber: bus?.plateNumber ?? "",
        routeId: trip.routeId,
        originCity: originLoc?.city ?? origin?.name ?? "—",
        destinationCity: destLoc?.city ?? destination?.name ?? "—",
        bookingCount: confirmedBookings.length,
        revenue,
        occupancyRate,
      });
    }

    // Sort by departure time desc
    tripRows.sort((a, b) => b.departureTime.localeCompare(a.departureTime));

    // Build filter options
    const busOptions = buses.map((b) => ({ _id: b._id, name: b.name, plateNumber: b.plateNumber }));
    const routeOptions = tripRows.reduce<Array<{ routeId: string; label: string }>>((acc, t) => {
      if (!acc.find((r) => r.routeId === t.routeId)) {
        acc.push({ routeId: t.routeId, label: `${t.originCity} → ${t.destinationCity}` });
      }
      return acc;
    }, []);
    const departureCities = [...new Set(tripRows.map((t) => t.originCity))].filter((c) => c !== "—");

    return {
      trips: tripRows,
      filters: {
        buses: busOptions,
        routes: routeOptions,
        departureCities,
      },
    };
  },
});

// ─── Travelers list (unique travelers for this company) ──────────────────────
export const getTravelers = query({
  args: {},
  handler: async (ctx) => {
    const { company } = await getOwnerCompanyForAnalytics(ctx);

    const trips = await ctx.db
      .query("trips")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    type TravelerRow = {
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

    const travelerMap = new Map<string, TravelerRow>();

    for (const trip of trips) {
      const bookings = await ctx.db
        .query("bookings")
        .withIndex("by_trip", (q) => q.eq("tripId", trip._id))
        .collect();

      const route = await ctx.db.get(trip.routeId);
      const origin = route ? await ctx.db.get(route.originStationId) : null;
      const destination = route ? await ctx.db.get(route.destinationStationId) : null;
      const originLoc = await resolveStationLocation(ctx, origin);
      const destLoc = await resolveStationLocation(ctx, destination);
      const routeLabel = `${originLoc?.city ?? origin?.name ?? "—"} → ${destLoc?.city ?? destination?.name ?? "—"}`;

      for (const b of bookings) {
        if (b.status === "cancelled") continue;

        const existing = travelerMap.get(b.travelerId);
        if (existing) {
          existing.totalBookings += 1;
          existing.totalSpent += b.totalPrice;
          // Update last trip if this is more recent
          if (!existing.lastTripDate || trip.departureTime > existing.lastTripDate) {
            existing.lastTripDate = trip.departureTime;
            existing.lastRoute = routeLabel;
          }
          // Update phone if available
          if (b.passengerPhone && !existing.phone) {
            existing.phone = b.passengerPhone;
          }
        } else {
          // Fetch user info
          const user = await ctx.db.get(b.travelerId);
          travelerMap.set(b.travelerId, {
            _id: b.travelerId,
            name: user?.name ?? b.passengerName,
            phone: user?.phone ?? b.passengerPhone,
            email: user?.email,
            totalBookings: 1,
            totalSpent: b.totalPrice,
            currency: b.currency,
            lastTripDate: trip.departureTime,
            lastRoute: routeLabel,
          });
        }
      }
    }

    const travelers = Array.from(travelerMap.values());
    // Sort by most bookings
    travelers.sort((a, b) => b.totalBookings - a.totalBookings);
    return travelers;
  },
});

// ─── Full ticket report (all bookings with enriched data for filtering) ─────
export const getTicketReport = query({
  args: {},
  handler: async (ctx) => {
    const { company } = await getOwnerCompanyForAnalytics(ctx);

    const trips = await ctx.db
      .query("trips")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    // Get all sellers for this company
    const allSellers = await ctx.db
      .query("users")
      .withIndex("by_role", (q) => q.eq("role", "seller"))
      .collect();
    const companySellers = allSellers.filter((s) => s.companyId === company._id);

    // Get all buses for this company
    const buses = await ctx.db
      .query("buses")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .collect();

    type TicketRow = {
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

    const tickets: TicketRow[] = [];

    for (const trip of trips) {
      const bookings = await ctx.db
        .query("bookings")
        .withIndex("by_trip", (q) => q.eq("tripId", trip._id))
        .collect();

      const route = await ctx.db.get(trip.routeId);
      const bus = await ctx.db.get(trip.busId);
      const origin = route ? await ctx.db.get(route.originStationId) : null;
      const destination = route ? await ctx.db.get(route.destinationStationId) : null;
      const originLoc = await resolveStationLocation(ctx, origin);
      const destLoc = await resolveStationLocation(ctx, destination);

      for (const b of bookings) {
        let sellerName: string | null = null;
        if (b.soldBySellerId) {
          const seller = await ctx.db.get(b.soldBySellerId);
          sellerName = seller?.name ?? null;
        }

        tickets.push({
          _id: b._id,
          _creationTime: b._creationTime,
          bookingReference: b.bookingReference,
          passengerName: b.passengerName,
          passengerPhone: b.passengerPhone,
          status: b.status,
          paymentStatus: b.paymentStatus,
          totalPrice: b.totalPrice,
          currency: b.currency,
          parcelCount: b.parcelCount,
          parcelWeight: b.parcelWeight,
          parcelAmount: b.parcelAmount,
          sellerId: b.soldBySellerId ?? null,
          sellerName,
          tripId: trip._id,
          routeId: trip.routeId,
          busId: trip.busId,
          busName: bus?.name ?? "—",
          busPlateNumber: bus?.plateNumber ?? "",
          originCity: originLoc?.city ?? origin?.name ?? "—",
          destinationCity: destLoc?.city ?? destination?.name ?? "—",
          departureTime: trip.departureTime,
          isReservation: !b.soldBySellerId,
        });
      }
    }

    // Sort by creation time desc
    tickets.sort((a, b) => b._creationTime - a._creationTime);

    // Return enriched metadata for filter dropdowns
    const sellerOptions = companySellers.map((s) => ({ _id: s._id, name: s.name ?? s.email ?? "Unknown" }));
    const busOptions = buses.map((b) => ({ _id: b._id, name: b.name, plateNumber: b.plateNumber }));
    const routeOptions = trips.reduce<Array<{ routeId: string; label: string }>>((acc, t) => {
      if (!acc.find((r) => r.routeId === t.routeId)) {
        const ticket = tickets.find((tk) => tk.routeId === t.routeId);
        if (ticket) {
          acc.push({ routeId: t.routeId, label: `${ticket.originCity} → ${ticket.destinationCity}` });
        }
      }
      return acc;
    }, []);
    const departureCities = [...new Set(tickets.map((t) => t.originCity))].filter((c) => c !== "—");

    return {
      tickets,
      filters: {
        sellers: sellerOptions,
        buses: busOptions,
        routes: routeOptions,
        departureCities,
      },
    };
  },
});
