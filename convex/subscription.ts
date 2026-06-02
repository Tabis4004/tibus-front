"use node";

import { action, internalAction } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";
import { internal } from "./_generated/api";

// Plan definitions
export const PLANS = {
  basic: {
    id: "basic",
    name: "Basic Plan",
    description: "Essential tools for small transport companies",
    monthlyAmount: 500000, // XAF 5,000 (Paystack uses smallest currency unit)
    currency: "XAF",
    features: ["Up to 5 buses", "Unlimited trips", "Up to 3 sellers", "Basic reporting"],
  },
  pro: {
    id: "pro",
    name: "Pro Plan",
    description: "Full power for growing transport companies",
    monthlyAmount: 1500000, // XAF 15,000
    currency: "XAF",
    features: ["Unlimited buses", "Unlimited trips", "Unlimited sellers", "Advanced analytics", "Priority support"],
  },
};

function paystackHeaders() {
  const key = process.env.PAYSTACK_SECRET_KEY;
  if (!key) throw new ConvexError({ message: "PAYSTACK_SECRET_KEY not configured", code: "EXTERNAL_SERVICE_ERROR" });
  return {
    Authorization: `Bearer ${key}`,
    "Content-Type": "application/json",
  };
}

// ─── Public actions ────────────────────────────────────────────────────────

export const initializeSubscription = action({
  args: {
    planId: v.string(),
    successUrl: v.string(),
    cancelUrl: v.string(),
  },
  handler: async (ctx, args): Promise<{ url: string }> => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const data = await ctx.runQuery(internal.subscriptionHelpers.getCompanyForOwner, {
      tokenIdentifier: identity.tokenIdentifier,
    });
    if (!data?.company) throw new ConvexError({ message: "No company found", code: "NOT_FOUND" });
    if (!data.user.email) throw new ConvexError({ message: "User email required for payment", code: "BAD_REQUEST" });

    // Look up plan from database first, fall back to legacy static PLANS
    const dbPlan = await ctx.runQuery(internal.subscriptionHelpers.getPlanById, { planId: args.planId });

    let planName: string;
    let planAmount: number;
    let planCurrency: string;

    if (dbPlan) {
      planName = dbPlan.name;
      planAmount = dbPlan.price;
      planCurrency = dbPlan.currency;
    } else {
      // Legacy fallback for "basic" / "pro"
      const legacyPlan = PLANS[args.planId as keyof typeof PLANS];
      if (!legacyPlan) throw new ConvexError({ message: "Invalid plan", code: "BAD_REQUEST" });
      planName = legacyPlan.name;
      planAmount = legacyPlan.monthlyAmount;
      planCurrency = legacyPlan.currency;
    }

    // Create/get Paystack customer
    let customerCode = data.company.paystackCustomerCode;
    if (!customerCode) {
      const custRes = await fetch("https://api.paystack.co/customer", {
        method: "POST",
        headers: paystackHeaders(),
        body: JSON.stringify({
          email: data.user.email,
          first_name: data.user.name?.split(" ")[0] ?? "",
          last_name: data.user.name?.split(" ").slice(1).join(" ") ?? "",
          metadata: { companyId: data.company._id, companyName: data.company.name },
        }),
      });
      const custJson = (await custRes.json()) as { status: boolean; data: { customer_code: string } };
      if (!custJson.status) throw new ConvexError({ message: "Failed to create Paystack customer", code: "EXTERNAL_SERVICE_ERROR" });
      customerCode = custJson.data.customer_code;
      await ctx.runMutation(internal.subscriptionHelpers.updateCompanySubscription, {
        companyId: data.company._id,
        subscriptionStatus: data.company.subscriptionStatus ?? "none",
        paystackCustomerCode: customerCode,
      });
    }

    // Initialize Paystack transaction
    const bodyPayload: Record<string, unknown> = {
      email: data.user.email,
      amount: planAmount,
      currency: planCurrency,
      callback_url: args.successUrl,
      metadata: {
        companyId: data.company._id,
        planId: args.planId,
        custom_fields: [
          { display_name: "Company", variable_name: "company", value: data.company.name },
          { display_name: "Plan", variable_name: "plan", value: planName },
        ],
      },
    };

    const txRes = await fetch("https://api.paystack.co/transaction/initialize", {
      method: "POST",
      headers: paystackHeaders(),
      body: JSON.stringify(bodyPayload),
    });
    const txJson = (await txRes.json()) as { status: boolean; data: { authorization_url: string } };
    if (!txJson.status) throw new ConvexError({ message: "Failed to initialize payment", code: "EXTERNAL_SERVICE_ERROR" });
    return { url: txJson.data.authorization_url };
  },
});

export const verifyPaystackTransaction = action({
  args: { reference: v.string() },
  handler: async (ctx, args): Promise<{ success: boolean; planId?: string }> => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const data = await ctx.runQuery(internal.subscriptionHelpers.getCompanyForOwner, {
      tokenIdentifier: identity.tokenIdentifier,
    });
    if (!data?.company) throw new ConvexError({ message: "No company found", code: "NOT_FOUND" });

    const res = await fetch(`https://api.paystack.co/transaction/verify/${args.reference}`, {
      headers: paystackHeaders(),
    });
    const json = (await res.json()) as {
      status: boolean;
      data: {
        status: string;
        metadata?: { planId?: string; companyId?: string };
        plan_object?: { plan_code: string };
        subscription?: { subscription_code: string; email_token: string };
        customer?: { customer_code: string };
      };
    };

    if (!json.status || json.data.status !== "success") {
      return { success: false };
    }

    const planId = (json.data.metadata?.planId as string | undefined) ?? "basic";
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();

    await ctx.runMutation(internal.subscriptionHelpers.updateCompanySubscription, {
      companyId: data.company._id,
      planId,
      subscriptionStatus: "active",
      planExpiresAt: expiresAt,
      paystackCustomerCode: json.data.customer?.customer_code ?? data.company.paystackCustomerCode,
      paystackSubscriptionCode: json.data.subscription?.subscription_code ?? data.company.paystackSubscriptionCode,
      paystackEmailToken: json.data.subscription?.email_token ?? data.company.paystackEmailToken,
    });

    return { success: true, planId };
  },
});

export const cancelSubscription = action({
  args: {},
  handler: async (ctx): Promise<{ success: boolean }> => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ message: "Not authenticated", code: "UNAUTHENTICATED" });

    const data = await ctx.runQuery(internal.subscriptionHelpers.getCompanyForOwner, {
      tokenIdentifier: identity.tokenIdentifier,
    });
    if (!data?.company) throw new ConvexError({ message: "No company found", code: "NOT_FOUND" });

    const { paystackSubscriptionCode, paystackEmailToken } = data.company;

    if (paystackSubscriptionCode && paystackEmailToken) {
      const res = await fetch("https://api.paystack.co/subscription/disable", {
        method: "POST",
        headers: paystackHeaders(),
        body: JSON.stringify({
          code: paystackSubscriptionCode,
          token: paystackEmailToken,
        }),
      });
      const json = (await res.json()) as { status: boolean };
      if (!json.status) throw new ConvexError({ message: "Failed to cancel subscription", code: "EXTERNAL_SERVICE_ERROR" });
    }

    await ctx.runMutation(internal.subscriptionHelpers.updateCompanySubscription, {
      companyId: data.company._id,
      planId: data.company.planId,
      subscriptionStatus: "cancelled",
      planExpiresAt: data.company.planExpiresAt,
    });

    return { success: true };
  },
});

// ─── Webhook handler logic ─────────────────────────────────────────────────

export const handlePaystackWebhook = internalAction({
  args: { event: v.string(), dataJson: v.string() },
  handler: async (ctx, args): Promise<void> => {
    const payload = JSON.parse(args.dataJson) as {
      customer?: { customer_code: string };
      subscription?: { subscription_code: string; email_token: string };
      plan?: { plan_code: string };
      metadata?: { companyId?: string; planId?: string };
      next_payment_date?: string;
    };

    const company = await ctx.runQuery(internal.subscriptionHelpers.getCompanyByPaystackCode, {
      paystackCustomerCode: payload.customer?.customer_code ?? "",
    });

    if (!company) return;

    if (args.event === "subscription.create" || args.event === "charge.success") {
      const planCode = payload.plan?.plan_code ?? "";
      const basicCode = process.env.PAYSTACK_BASIC_PLAN_CODE ?? "";
      const proCode = process.env.PAYSTACK_PRO_PLAN_CODE ?? "";
      let planId = company.planId ?? "basic";
      if (planCode && basicCode && planCode === basicCode) planId = "basic";
      if (planCode && proCode && planCode === proCode) planId = "pro";

      const expiresAt = payload.next_payment_date
        ? new Date(payload.next_payment_date).toISOString()
        : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();

      await ctx.runMutation(internal.subscriptionHelpers.updateCompanySubscription, {
        companyId: company._id,
        planId,
        subscriptionStatus: "active",
        planExpiresAt: expiresAt,
        paystackSubscriptionCode: payload.subscription?.subscription_code ?? company.paystackSubscriptionCode,
        paystackEmailToken: payload.subscription?.email_token ?? company.paystackEmailToken,
      });
    } else if (args.event === "subscription.disable" || args.event === "subscription.not_renew") {
      await ctx.runMutation(internal.subscriptionHelpers.updateCompanySubscription, {
        companyId: company._id,
        planId: company.planId,
        subscriptionStatus: "cancelled",
        planExpiresAt: company.planExpiresAt,
      });
    } else if (args.event === "invoice.payment_failed") {
      await ctx.runMutation(internal.subscriptionHelpers.updateCompanySubscription, {
        companyId: company._id,
        planId: company.planId,
        subscriptionStatus: "past_due",
        planExpiresAt: company.planExpiresAt,
      });
    }
  },
});
