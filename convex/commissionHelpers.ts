import type { MutationCtx } from "./_generated/server";
import type { Id } from "./_generated/dataModel.d.ts";

/**
 * After a booking is created, check if the company has a commission setting.
 * If so, create a commission entry and update the booking with commission info.
 */
export async function recordCommission(
  ctx: MutationCtx,
  bookingId: Id<"bookings">,
  companyId: Id<"companies">,
  ticketPrice: number,
  currency: string,
) {
  const settings = await ctx.db
    .query("companyCommissions")
    .withIndex("by_company", (q) => q.eq("companyId", companyId))
    .first();

  if (!settings || settings.rate <= 0) return;

  const commissionAmount = Math.round((ticketPrice * settings.rate) / 100);
  if (commissionAmount <= 0) return;

  // Update the booking with commission info
  await ctx.db.patch(bookingId, {
    commissionAmount,
    commissionPaidBy: settings.paidBy,
  });

  // Create a ledger entry
  await ctx.db.insert("commissionEntries", {
    companyId,
    bookingId,
    amount: commissionAmount,
    currency,
    paidBy: settings.paidBy,
    status: "pending",
  });
}
