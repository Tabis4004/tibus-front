import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";
import { paginationOptsValidator } from "convex/server";

// ─── Queries ─────────────────────────────────────────────────────────────────

/**
 * Get reviews for a company (public, paginated)
 */
export const listByCompany = query({
  args: {
    companyId: v.id("companies"),
    paginationOpts: paginationOptsValidator,
  },
  handler: async (ctx, args) => {
    const results = await ctx.db
      .query("reviews")
      .withIndex("by_company", (q) => q.eq("companyId", args.companyId))
      .order("desc")
      .paginate(args.paginationOpts);

    // Hydrate traveler info
    const page = await Promise.all(
      results.page.map(async (review) => {
        const traveler = await ctx.db.get(review.travelerId);
        const trip = await ctx.db.get(review.tripId);
        const route = trip ? await ctx.db.get(trip.routeId) : null;
        const origin = route ? await ctx.db.get(route.originStationId) : null;
        const destination = route ? await ctx.db.get(route.destinationStationId) : null;

        return {
          ...review,
          travelerName: traveler?.name ?? "Traveler",
          routeLabel: origin && destination ? `${origin.name} → ${destination.name}` : null,
          departureTime: trip?.departureTime ?? null,
        };
      })
    );

    return { ...results, page };
  },
});

/**
 * Get aggregated rating stats for a company
 */
export const getCompanyStats = query({
  args: { companyId: v.id("companies") },
  handler: async (ctx, args) => {
    const allReviews = await ctx.db
      .query("reviews")
      .withIndex("by_company", (q) => q.eq("companyId", args.companyId))
      .collect();

    if (allReviews.length === 0) {
      return { averageRating: 0, totalReviews: 0, distribution: [0, 0, 0, 0, 0] };
    }

    const total = allReviews.length;
    const sum = allReviews.reduce((acc, r) => acc + r.rating, 0);
    const avg = sum / total;

    // Rating distribution [1-star, 2-star, 3-star, 4-star, 5-star]
    const distribution = [0, 0, 0, 0, 0];
    for (const r of allReviews) {
      distribution[r.rating - 1]++;
    }

    return { averageRating: Math.round(avg * 10) / 10, totalReviews: total, distribution };
  },
});

/**
 * Check if traveler can review a specific booking
 */
export const canReview = query({
  args: { bookingId: v.id("bookings") },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return { canReview: false, reason: "unauthenticated" };

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) return { canReview: false, reason: "no_user" };

    const booking = await ctx.db.get(args.bookingId);
    if (!booking) return { canReview: false, reason: "booking_not_found" };
    if (booking.travelerId !== user._id) return { canReview: false, reason: "not_your_booking" };

    // Only allow review for completed/collected trips
    const trip = await ctx.db.get(booking.tripId);
    if (!trip) return { canReview: false, reason: "trip_not_found" };

    const tripPassed = new Date(trip.departureTime) < new Date();
    const validStatus = booking.status === "confirmed" || booking.status === "collected";
    if (!tripPassed || !validStatus) {
      return { canReview: false, reason: "trip_not_completed" };
    }

    // Check if already reviewed
    const existing = await ctx.db
      .query("reviews")
      .withIndex("by_booking", (q) => q.eq("bookingId", args.bookingId))
      .first();
    if (existing) return { canReview: false, reason: "already_reviewed", reviewId: existing._id };

    return { canReview: true, reason: "ok" };
  },
});

/**
 * List reviews for the owner's company (with full traveler details)
 */
export const listForOwner = query({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });

    const company = await ctx.db
      .query("companies")
      .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
      .first();
    if (!company) throw new ConvexError({ message: "No company found", code: "NOT_FOUND" });

    const results = await ctx.db
      .query("reviews")
      .withIndex("by_company", (q) => q.eq("companyId", company._id))
      .order("desc")
      .paginate(args.paginationOpts);

    const page = await Promise.all(
      results.page.map(async (review) => {
        const traveler = await ctx.db.get(review.travelerId);
        const trip = await ctx.db.get(review.tripId);
        const route = trip ? await ctx.db.get(trip.routeId) : null;
        const origin = route ? await ctx.db.get(route.originStationId) : null;
        const destination = route ? await ctx.db.get(route.destinationStationId) : null;

        return {
          ...review,
          travelerName: traveler?.name ?? "Traveler",
          travelerEmail: traveler?.email,
          routeLabel: origin && destination ? `${origin.name} → ${destination.name}` : null,
          departureTime: trip?.departureTime ?? null,
        };
      })
    );

    return { ...results, page };
  },
});

// ─── Mutations ───────────────────────────────────────────────────────────────

/**
 * Submit a review for a completed trip
 */
export const submitReview = mutation({
  args: {
    bookingId: v.id("bookings"),
    rating: v.number(),
    comment: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });

    if (args.rating < 1 || args.rating > 5) {
      throw new ConvexError({ message: "Rating must be between 1 and 5", code: "BAD_REQUEST" });
    }

    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new ConvexError({ message: "Booking not found", code: "NOT_FOUND" });
    if (booking.travelerId !== user._id) {
      throw new ConvexError({ message: "Not your booking", code: "FORBIDDEN" });
    }

    // Verify trip has passed
    const trip = await ctx.db.get(booking.tripId);
    if (!trip) throw new ConvexError({ message: "Trip not found", code: "NOT_FOUND" });
    if (new Date(trip.departureTime) > new Date()) {
      throw new ConvexError({ message: "Trip has not departed yet", code: "BAD_REQUEST" });
    }

    // No duplicate reviews
    const existing = await ctx.db
      .query("reviews")
      .withIndex("by_booking", (q) => q.eq("bookingId", args.bookingId))
      .first();
    if (existing) {
      throw new ConvexError({ message: "You have already reviewed this trip", code: "CONFLICT" });
    }

    return await ctx.db.insert("reviews", {
      companyId: trip.companyId,
      tripId: booking.tripId,
      bookingId: args.bookingId,
      travelerId: user._id,
      rating: args.rating,
      comment: args.comment,
    });
  },
});

/**
 * Owner replies to a review
 */
export const replyToReview = mutation({
  args: {
    reviewId: v.id("reviews"),
    reply: v.string(),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const user = await ctx.db
      .query("users")
      .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
      .unique();
    if (!user) throw new ConvexError({ message: "User not found", code: "NOT_FOUND" });

    const review = await ctx.db.get(args.reviewId);
    if (!review) throw new ConvexError({ message: "Review not found", code: "NOT_FOUND" });

    // Verify owner
    const company = await ctx.db.get(review.companyId);
    if (!company || company.ownerId !== user._id) {
      throw new ConvexError({ message: "Only the company owner can reply", code: "FORBIDDEN" });
    }

    await ctx.db.patch(args.reviewId, {
      ownerReply: args.reply,
      ownerRepliedAt: new Date().toISOString(),
    });
  },
});
