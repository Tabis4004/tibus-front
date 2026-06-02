import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

// Roles: "traveler" | "owner" | "seller" | "superadmin"

export default defineSchema({
  users: defineTable({
    tokenIdentifier: v.string(),
    name: v.optional(v.string()),
    email: v.optional(v.string()),
    avatar: v.optional(v.string()),
    role: v.optional(v.string()),
    // Profile completion fields
    username: v.optional(v.string()),
    phone: v.optional(v.string()),
    countryId: v.optional(v.id("countries")),
    profileCompleted: v.optional(v.boolean()),
    onboardingCompleted: v.optional(v.boolean()),
    // For sellers: which company they belong to
    companyId: v.optional(v.id("companies")),
  })
    .index("by_token", ["tokenIdentifier"])
    .index("by_role", ["role"])
    .index("by_username", ["username"])
    .index("by_phone", ["phone"])
    .searchIndex("search_name", { searchField: "name" }),

  // Per-role permission overrides (managed by superadmin)
  rolePermissions: defineTable({
    role: v.string(),
    permissions: v.array(v.string()),
    updatedBy: v.id("users"),
  }).index("by_role", ["role"]),

  // Custom roles created by SuperAdmin (matching SQL Role table)
  roles: defineTable({
    name: v.string(),
    permissions: v.array(v.string()), // "droits" - list of permission keys
  }).index("by_name", ["name"]),

  // User-role-company assignments (matching SQL UserRoles table)
  userRoles: defineTable({
    userId: v.id("users"),
    roleId: v.id("roles"),
    companyId: v.optional(v.id("companies")),
  })
    .index("by_user", ["userId"])
    .index("by_role", ["roleId"])
    .index("by_company", ["companyId"]),

  // ─── Global geography (not company-scoped) ─────────────────────────────────
  countries: defineTable({
    name: v.string(),
  }).index("by_name", ["name"]),

  cities: defineTable({
    countryId: v.id("countries"),
    name: v.string(),
  })
    .index("by_country", ["countryId"])
    .index("by_name", ["name"]),

  companies: defineTable({
    ownerId: v.id("users"),
    name: v.string(),
    description: v.optional(v.string()),
    logoUrl: v.optional(v.string()),
    logoStorageId: v.optional(v.id("_storage")), // Convex File Storage ID for uploaded logo
    phone: v.optional(v.string()),
    email: v.optional(v.string()),
    website: v.optional(v.string()),
    isActive: v.boolean(),
    // Country & address
    countryId: v.optional(v.id("countries")),
    address: v.optional(v.string()),
    // Boarding warning message shown on tickets (set by company owner)
    boardingMessage: v.optional(v.string()),
    // Fiscal & banking info for corporate receipts
    nif: v.optional(v.string()),
    rccm: v.optional(v.string()),
    tva: v.optional(v.string()),
    bankAccount: v.optional(v.string()),
    // Subscription
    planId: v.optional(v.string()), // legacy "basic" | "pro"
    subscriptionPlanId: v.optional(v.id("subscriptionPlans")), // New: references subscriptionPlans table
    subscriptionStatus: v.optional(v.string()), // "trial" | "active" | "past_due" | "cancelled" | "expired" | "none"
    planExpiresAt: v.optional(v.string()),
    // Paystack
    paystackCustomerCode: v.optional(v.string()),
    paystackSubscriptionCode: v.optional(v.string()),
    paystackEmailToken: v.optional(v.string()),
  }).index("by_owner", ["ownerId"]),

  buses: defineTable({
    companyId: v.id("companies"),
    name: v.string(),
    plateNumber: v.string(),
    capacity: v.number(),
    busType: v.string(), // "standard" | "luxury" | "mini"
    amenities: v.optional(v.array(v.string())),
    isActive: v.boolean(),
  }).index("by_company", ["companyId"]),

  // Legacy table – kept for backward compatibility with old data
  locations: defineTable({
    companyId: v.id("companies"),
    city: v.string(),
    country: v.string(),
  }).index("by_company", ["companyId"]),

  stations: defineTable({
    companyId: v.id("companies"),
    // New: global city reference
    cityId: v.optional(v.id("cities")),
    // Legacy: kept for old data
    locationId: v.optional(v.id("locations")),
    name: v.string(),
    address: v.string(),
    // Geolocation
    latitude: v.optional(v.number()),
    longitude: v.optional(v.number()),
    isActive: v.boolean(),
  })
    .index("by_company", ["companyId"])
    .index("by_location", ["locationId"]),

  routes: defineTable({
    companyId: v.id("companies"),
    originStationId: v.id("stations"),
    destinationStationId: v.id("stations"),
    estimatedDurationMinutes: v.number(),
    isActive: v.boolean(),
  }).index("by_company", ["companyId"]),

  trips: defineTable({
    companyId: v.id("companies"),
    routeId: v.id("routes"),
    busId: v.id("buses"),
    departureTime: v.string(),
    arrivalTime: v.string(),
    priceAmount: v.number(),
    currency: v.string(),
    seatsAvailable: v.number(),
    totalSeats: v.number(),
    status: v.string(), // "scheduled" | "active" | "cancelled" | "completed"
  })
    .index("by_company", ["companyId"])
    .index("by_route", ["routeId"])
    .index("by_departure", ["departureTime"]),

  bookings: defineTable({
    tripId: v.id("trips"),
    travelerId: v.id("users"),
    soldBySellerId: v.optional(v.id("users")),
    passengerName: v.string(),
    passengerPhone: v.optional(v.string()),
    seatNumber: v.optional(v.string()),
    status: v.string(), // "pending_payment" | "confirmed" | "cancelled" | "collected"
    totalPrice: v.number(),
    currency: v.string(),
    bookingReference: v.string(),
    // Parcels
    parcelCount: v.optional(v.number()),
    parcelWeight: v.optional(v.number()), // kg
    parcelAmount: v.optional(v.number()), // price for parcels
    // Payment
    paymentStatus: v.optional(v.string()), // "pending" | "paid" | "refunded"
    paystackReference: v.optional(v.string()),
    // Commission
    commissionAmount: v.optional(v.number()),
    commissionPaidBy: v.optional(v.string()), // "traveler" | "company"
  })
    .index("by_trip", ["tripId"])
    .index("by_traveler", ["travelerId"])
    .index("by_seller", ["soldBySellerId"])
    .index("by_reference", ["bookingReference"]),

  // ─── Subscription Plans (managed by SuperAdmin) ─────────────────────────────
  subscriptionPlans: defineTable({
    name: v.string(), // e.g. "Monthly", "Quarterly", "Yearly", "Trial"
    durationDays: v.number(), // How many days the plan lasts
    price: v.number(), // Price in smallest currency unit
    currency: v.string(), // e.g. "XAF"
    isDefault: v.boolean(), // If true, auto-assigned on company creation (trial)
    isActive: v.boolean(), // Whether this plan is available for selection
  }).index("by_active", ["isActive"]),

  // ─── Company-Traveler relationship (cross-company client lists) ─────────────
  companyTravelers: defineTable({
    companyId: v.id("companies"),
    travelerId: v.id("users"),
  })
    .index("by_company", ["companyId"])
    .index("by_traveler", ["travelerId"])
    .index("by_company_and_traveler", ["companyId", "travelerId"]),

  // ─── Commission settings per company ────────────────────────────────────────
  companyCommissions: defineTable({
    companyId: v.id("companies"),
    rate: v.number(), // Percentage 0-100
    paidBy: v.string(), // "traveler" | "company"
    updatedBy: v.id("users"),
  }).index("by_company", ["companyId"]),

  // ─── Commission ledger (one entry per booking) ──────────────────────────────
  commissionEntries: defineTable({
    companyId: v.id("companies"),
    bookingId: v.id("bookings"),
    amount: v.number(),
    currency: v.string(),
    paidBy: v.string(), // "traveler" | "company"
    status: v.string(), // "pending" | "paid"
    paidAt: v.optional(v.string()), // ISO date when marked paid
  })
    .index("by_company", ["companyId"])
    .index("by_booking", ["bookingId"])
    .index("by_status", ["status"]),

  // ─── In-app notifications ───────────────────────────────────────────────────
  notifications: defineTable({
    userId: v.id("users"),
    type: v.string(), // "booking_confirmed" | "booking_cancelled" | "trip_reminder" | "trip_cancelled" | "new_booking" | "system"
    title: v.string(),
    message: v.string(),
    isRead: v.boolean(),
    relatedBookingId: v.optional(v.id("bookings")),
    relatedTripId: v.optional(v.id("trips")),
  })
    .index("by_user", ["userId"])
    .index("by_user_and_read", ["userId", "isRead"]),

  // ─── Push notification identity mapping ─────────────────────────────────────────
  pushIdentities: defineTable({
    secret: v.string(),
    visitorId: v.string(),
  })
    .index("by_secret", ["secret"])
    .index("by_visitorId", ["visitorId"]),

  // ─── Landing page CMS content (managed by superadmin) ────────────────────────
  landingContent: defineTable({
    section: v.string(), // "hero" | "stats" | "features_travelers" | "features_companies" | "testimonials" | "trust_signals" | "how_it_works" | "cta" | "footer"
    content: v.string(), // JSON-encoded content for that section
    updatedBy: v.id("users"),
  }).index("by_section", ["section"]),

  // ─── Contact / WhatsApp settings ──────────────────────────────────────────────
  contactSettings: defineTable({
    // "platform" for the global Tibus whatsapp, or companyId for per-company
    scope: v.string(), // "platform" | companyId string
    whatsappNumber: v.string(), // e.g. "+237612345678"
    updatedBy: v.id("users"),
  }).index("by_scope", ["scope"]),

  // ─── Contact inquiries submitted by users ─────────────────────────────────────
  contactInquiries: defineTable({
    name: v.string(),
    email: v.string(),
    phone: v.optional(v.string()),
    inquiryTo: v.string(), // "platform" | companyId
    message: v.string(),
    status: v.string(), // "new" | "read" | "resolved"
  }).index("by_inquiryTo", ["inquiryTo"])
    .index("by_status", ["status"]),

  // ─── Reviews & ratings ──────────────────────────────────────────────────────
  reviews: defineTable({
    companyId: v.id("companies"),
    tripId: v.id("trips"),
    bookingId: v.id("bookings"),
    travelerId: v.id("users"),
    rating: v.number(), // 1-5
    comment: v.optional(v.string()),
    ownerReply: v.optional(v.string()),
    ownerRepliedAt: v.optional(v.string()), // ISO
  })
    .index("by_company", ["companyId"])
    .index("by_traveler", ["travelerId"])
    .index("by_booking", ["bookingId"]),

  // ─── Promotional codes ─────────────────────────────────────────────────────
  promoCodes: defineTable({
    companyId: v.id("companies"),
    code: v.string(), // Unique per company, uppercase
    discountType: v.string(), // "percentage" | "fixed"
    discountValue: v.number(), // e.g. 10 for 10% or 500 for 500 XAF
    currency: v.optional(v.string()), // Required for fixed discounts
    validFrom: v.string(), // ISO date
    validUntil: v.string(), // ISO date
    maxUsage: v.optional(v.number()), // Max total uses (null = unlimited)
    usageCount: v.number(), // Current uses
    routeId: v.optional(v.id("routes")), // Restrict to specific route (null = all routes)
    isActive: v.boolean(),
  })
    .index("by_company", ["companyId"])
    .index("by_company_and_code", ["companyId", "code"]),
});
