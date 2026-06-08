import { useEffect, useState } from "react";
import { useParams, Link } from "react-router-dom";
import {
  BuildingIcon,
  CalendarIcon,
  MessageSquareIcon,
} from "lucide-react";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Button } from "@/components/ui/button.tsx";
import StarRating from "@/components/ui/star-rating.tsx";
import { useTranslation } from "react-i18next";
import { formatDistanceToNow } from "date-fns";
import { fr, enUS } from "date-fns/locale";
import {
  getCompanyByIdSupabase,
  getCompanyReviewStatsSupabase,
  listCompanyReviewsSupabase,
  type PublicCompanyProfile,
  type CompanyReviewStats,
  type CompanyReview,
} from "@/lib/supabase/companies-public";

export default function SupabaseCompanyProfile() {
  const { t } = useTranslation(["traveler", "common"]);
  const { companyId, lng } = useParams<{ companyId: string; lng: string }>();
  const dateLocale = lng === "fr" ? fr : enUS;
  const [company, setCompany] = useState<PublicCompanyProfile | null | undefined>(undefined);
  const [stats, setStats] = useState<CompanyReviewStats | null>(null);
  const [reviews, setReviews] = useState<CompanyReview[]>([]);

  useEffect(() => {
    if (!companyId) return;
    let cancelled = false;
    void Promise.all([
      getCompanyByIdSupabase(companyId),
      getCompanyReviewStatsSupabase(companyId),
      listCompanyReviewsSupabase(companyId, 10),
    ])
      .then(([companyRow, statsRow, reviewRows]) => {
        if (!cancelled) {
          setCompany(companyRow);
          setStats(statsRow);
          setReviews(reviewRows);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setCompany(null);
          setStats(null);
          setReviews([]);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [companyId]);

  if (company === undefined) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-8 space-y-4">
        <Skeleton className="h-40 w-full rounded-2xl" />
        <Skeleton className="h-6 w-48" />
        <Skeleton className="h-4 w-full" />
      </div>
    );
  }

  if (!company) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-16 text-center text-muted-foreground">
        <BuildingIcon className="w-12 h-12 mx-auto mb-4 opacity-30" />
        <p className="font-medium">{t("no_companies", { ns: "traveler" })}</p>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div className="relative rounded-2xl overflow-hidden bg-gradient-to-br from-primary/20 via-primary/10 to-transparent h-36 flex items-end p-4">
        <div className="flex items-end gap-4">
          <div className="w-16 h-16 rounded-2xl border-4 border-background bg-white flex items-center justify-center overflow-hidden">
            {company.logo ? (
              <img src={company.logo} alt={company.name} className="w-full h-full object-cover" />
            ) : (
              <BuildingIcon className="w-7 h-7 text-primary" />
            )}
          </div>
          <div>
            <h1 className="text-xl font-extrabold text-foreground">{company.name}</h1>
            <div className="flex items-center gap-2 mt-0.5">
              <Badge variant={company.isActive ? "default" : "secondary"} className="text-[10px]">
                {company.isActive
                  ? t("status.active", { ns: "common" })
                  : t("status.inactive", { ns: "common" })}
              </Badge>
              {stats && stats.totalReviews > 0 && (
                <div className="flex items-center gap-1">
                  <StarRating rating={stats.averageRating} size="sm" />
                  <span className="text-xs text-muted-foreground">({stats.totalReviews})</span>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>

      {company.managerName && (
        <p className="text-sm text-muted-foreground">
          {t("labels.manager", { ns: "common", defaultValue: "Responsable" })} :{" "}
          {company.managerName}
        </p>
      )}

      {company.voyageColisMsg && (
        <p className="text-sm text-muted-foreground leading-relaxed">{company.voyageColisMsg}</p>
      )}

      <div className="p-4 rounded-xl bg-muted flex items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <CalendarIcon className="w-5 h-5 text-primary" />
          <div>
            <p className="text-sm font-semibold">{t("available_trips_cta", { ns: "traveler" })}</p>
            <p className="text-xs text-muted-foreground">
              {t("available_trips_cta_desc", { ns: "traveler" })}
            </p>
          </div>
        </div>
        <Link to={`/${lng}/traveler/search?companyId=${company.id}`}>
          <Button size="sm" className="shrink-0">
            {t("view_trips_btn", { ns: "traveler" })}
          </Button>
        </Link>
      </div>

      <div className="space-y-4">
        <h3 className="text-sm font-semibold flex items-center gap-1.5">
          <MessageSquareIcon className="w-4 h-4 text-primary" />
          {t("reviews.section_title", { ns: "traveler" })}
        </h3>

        {stats && stats.totalReviews > 0 && (
          <div className="rounded-xl border p-4 flex items-center gap-3">
            <span className="text-3xl font-black">{stats.averageRating}</span>
            <div>
              <StarRating rating={stats.averageRating} size="md" />
              <p className="text-xs text-muted-foreground mt-0.5">
                {stats.totalReviews} {t("reviews.reviews_count", { ns: "traveler" })}
              </p>
            </div>
          </div>
        )}

        {reviews.length === 0 ? (
          <p className="text-sm text-muted-foreground">{t("reviews.none_yet", { ns: "traveler" })}</p>
        ) : (
          <div className="space-y-3">
            {reviews.map((review) => (
              <div key={review.id} className="rounded-xl border p-4 space-y-2">
                <div className="flex items-center justify-between gap-2">
                  <StarRating rating={review.rating} size="sm" />
                  <span className="text-[10px] text-muted-foreground">
                    {formatDistanceToNow(new Date(review.createdAt), {
                      addSuffix: true,
                      locale: dateLocale,
                    })}
                  </span>
                </div>
                {review.comment && (
                  <p className="text-sm text-muted-foreground">{review.comment}</p>
                )}
                {review.ownerReply && (
                  <div className="rounded-lg bg-muted p-2 text-xs">{review.ownerReply}</div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
