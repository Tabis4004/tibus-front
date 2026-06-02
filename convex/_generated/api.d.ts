/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as adminManage from "../adminManage.js";
import type * as analytics from "../analytics.js";
import type * as bookings from "../bookings.js";
import type * as commissionHelpers from "../commissionHelpers.js";
import type * as commissions from "../commissions.js";
import type * as companies from "../companies.js";
import type * as contact from "../contact.js";
import type * as fedaPayment from "../fedaPayment.js";
import type * as fleet from "../fleet.js";
import type * as geography from "../geography.js";
import type * as http from "../http.js";
import type * as landingContent from "../landingContent.js";
import type * as notifications from "../notifications.js";
import type * as promoCodes from "../promoCodes.js";
import type * as pushIdentities from "../pushIdentities.js";
import type * as pushNotifications from "../pushNotifications.js";
import type * as reviews from "../reviews.js";
import type * as roleManagement from "../roleManagement.js";
import type * as sellerTickets from "../sellerTickets.js";
import type * as sellers from "../sellers.js";
import type * as stationHelpers from "../stationHelpers.js";
import type * as subscription from "../subscription.js";
import type * as subscriptionHelpers from "../subscriptionHelpers.js";
import type * as subscriptionPlans from "../subscriptionPlans.js";
import type * as ticketPayment from "../ticketPayment.js";
import type * as ticketPaymentHelpers from "../ticketPaymentHelpers.js";
import type * as trips from "../trips.js";
import type * as users from "../users.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  adminManage: typeof adminManage;
  analytics: typeof analytics;
  bookings: typeof bookings;
  commissionHelpers: typeof commissionHelpers;
  commissions: typeof commissions;
  companies: typeof companies;
  contact: typeof contact;
  fedaPayment: typeof fedaPayment;
  fleet: typeof fleet;
  geography: typeof geography;
  http: typeof http;
  landingContent: typeof landingContent;
  notifications: typeof notifications;
  promoCodes: typeof promoCodes;
  pushIdentities: typeof pushIdentities;
  pushNotifications: typeof pushNotifications;
  reviews: typeof reviews;
  roleManagement: typeof roleManagement;
  sellerTickets: typeof sellerTickets;
  sellers: typeof sellers;
  stationHelpers: typeof stationHelpers;
  subscription: typeof subscription;
  subscriptionHelpers: typeof subscriptionHelpers;
  subscriptionPlans: typeof subscriptionPlans;
  ticketPayment: typeof ticketPayment;
  ticketPaymentHelpers: typeof ticketPaymentHelpers;
  trips: typeof trips;
  users: typeof users;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
