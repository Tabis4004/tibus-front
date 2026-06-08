import { supabase } from "@/lib/supabase";

export type PublicCompanyProfile = {
  id: string;
  name: string;
  logo: string | null;
  managerName: string | null;
  isActive: boolean;
  currency: string;
  voyageColisMsg: string | null;
};

export type CompanyReviewStats = {
  averageRating: number;
  totalReviews: number;
  distribution: number[];
};

export type CompanyReview = {
  id: string;
  rating: number;
  comment: string | null;
  ownerReply: string | null;
  ownerRepliedAt: string | null;
  createdAt: string;
  travelerName: string;
};

export async function getCompanyByIdSupabase(
  companyId: string,
): Promise<PublicCompanyProfile | null> {
  const { data, error } = await supabase
    .from("Companies")
    .select("id, name, logo, managerName, isActive, countryId, voyageColisMsg")
    .eq("id", companyId)
    .maybeSingle();

  if (error) throw error;
  if (!data) return null;

  const { data: country, error: countryError } = await supabase
    .from("Countries")
    .select("currency")
    .eq("id", data.countryId as string)
    .maybeSingle();

  if (countryError) throw countryError;

  return {
    id: data.id as string,
    name: data.name as string,
    logo: (data.logo as string | null) ?? null,
    managerName: (data.managerName as string | null) ?? null,
    isActive: Boolean(data.isActive),
    currency: (country?.currency as string | null) ?? "XOF",
    voyageColisMsg: (data.voyageColisMsg as string | null) ?? null,
  };
}

export async function getCompanyReviewStatsSupabase(
  companyId: string,
): Promise<CompanyReviewStats> {
  const { data, error } = await supabase
    .from("Reviews")
    .select("rating")
    .eq("companyId", companyId);

  if (error) throw error;

  const distribution = [0, 0, 0, 0, 0];
  for (const row of data ?? []) {
    const rating = row.rating as number;
    if (rating >= 1 && rating <= 5) {
      distribution[rating - 1] += 1;
    }
  }

  const totalReviews = (data ?? []).length;
  const averageRating =
    totalReviews > 0
      ? Math.round(
          ((data ?? []).reduce((sum, row) => sum + (row.rating as number), 0) /
            totalReviews) *
            10,
        ) / 10
      : 0;

  return { averageRating, totalReviews, distribution };
}

export async function listCompanyReviewsSupabase(
  companyId: string,
  limit = 20,
  offset = 0,
): Promise<CompanyReview[]> {
  const { data, error } = await supabase
    .from("Reviews")
    .select(
      "id, rating, comment, ownerReply, ownerRepliedAt, createdAt, Users(firstName, lastName, email)",
    )
    .eq("companyId", companyId)
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
