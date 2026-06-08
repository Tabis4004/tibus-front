import { supabase } from "@/lib/supabase";
import { resolveOwnerCompanyId } from "@/lib/supabase/owner-company";

export type OwnerReviewRow = {
  id: string;
  rating: number;
  comment: string | null;
  ownerReply: string | null;
  ownerRepliedAt: string | null;
  createdAt: string;
  travelerName: string;
};

export async function listOwnerReviewsSupabase(
  appUserId: string,
  companyId?: string | null,
  limit = 20,
  offset = 0,
): Promise<OwnerReviewRow[]> {
  const resolvedCompanyId = await resolveOwnerCompanyId(appUserId, companyId);
  if (!resolvedCompanyId) return [];

  const { data, error } = await supabase
    .from("Reviews")
    .select(
      "id, rating, comment, ownerReply, ownerRepliedAt, createdAt, Users(firstName, lastName, email)",
    )
    .eq("companyId", resolvedCompanyId)
    .order("createdAt", { ascending: false })
    .range(offset, offset + limit - 1);

  if (error) throw error;

  return (data ?? []).map((row) => {
    const user = Array.isArray(row.Users) ? row.Users[0] : row.Users;
    const userRow = user as
      | { firstName?: string | null; lastName?: string | null; email?: string | null }
      | null
      | undefined;
    const travelerName =
      [userRow?.firstName, userRow?.lastName].filter(Boolean).join(" ").trim() ||
      userRow?.email ||
      "Voyageur";

    return {
      id: row.id as string,
      rating: row.rating as number,
      comment: (row.comment as string | null) ?? null,
      ownerReply: (row.ownerReply as string | null) ?? null,
      ownerRepliedAt: (row.ownerRepliedAt as string | null) ?? null,
      createdAt: row.createdAt as string,
      travelerName,
    };
  });
}

export async function replyToReviewSupabase(
  reviewId: string,
  reply: string,
): Promise<void> {
  const { error } = await supabase
    .from("Reviews")
    .update({
      ownerReply: reply.trim(),
      ownerRepliedAt: new Date().toISOString(),
    })
    .eq("id", reviewId);

  if (error) throw error;
}
