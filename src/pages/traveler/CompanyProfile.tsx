import { useParams, Link } from "react-router-dom";
import { useQuery, usePaginatedQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import {
  BuildingIcon,
  PhoneIcon,
  MailIcon,
  GlobeIcon,
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

export default function CompanyProfile() {
  const { t } = useTranslation(["traveler", "common"]);
  const { companyId, lng } = useParams<{ companyId: string; lng: string }>();
  const company = useQuery(
    api.companies.getCompanyById,
    companyId ? { companyId: companyId as Id<"companies"> } : "skip"
  );
  const stats = useQuery(
    api.reviews.getCompanyStats,
    companyId ? { companyId: companyId as Id<"companies"> } : "skip"
  );
  const { results: reviews, status: loadStatus, loadMore } = usePaginatedQuery(
    api.reviews.listByCompany,
    companyId ? { companyId: companyId as Id<"companies"> } : "skip",
    { initialNumItems: 5 }
  );

  const dateLocale = lng === "fr" ? fr : enUS;

  if (company === undefined) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-8 space-y-4">
        <Skeleton className="h-40 w-full rounded-2xl" />
        <Skeleton className="h-6 w-48" />
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-3/4" />
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
      {/* Hero */}
      <div className="relative rounded-2xl overflow-hidden bg-gradient-to-br from-primary/20 via-primary/10 to-transparent h-36 flex items-end p-4">
        <div className="flex items-end gap-4">
          <div className="w-16 h-16 rounded-2xl border-4 border-background bg-white flex items-center justify-center overflow-hidden">
            {company.logoUrl ? (
              <img src={company.logoUrl} alt={company.name} className="w-full h-full object-cover" />
            ) : (
              <BuildingIcon className="w-7 h-7 text-primary" />
            )}
          </div>
          <div>
            <h1 className="text-xl font-extrabold text-foreground">{company.name}</h1>
            <div className="flex items-center gap-2 mt-0.5">
              <Badge variant={company.isActive ? "default" : "secondary"} className="text-[10px]">
                {company.isActive ? t("status.active", { ns: "common" }) : t("status.inactive", { ns: "common" })}
              </Badge>
              {stats && stats.totalReviews > 0 && (
                <div className="flex items-center gap-1">
                  <StarRating rating={stats.averageRating} size="sm" />
                  <span className="text-xs text-muted-foreground">
                    ({stats.totalReviews})
                  </span>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Description */}
      {company.description && (
        <p className="text-sm text-muted-foreground leading-relaxed">{company.description}</p>
      )}

      {/* Contact */}
      <div className="space-y-2">
        <h3 className="text-sm font-semibold">{t("labels.contact", { ns: "common" })}</h3>
        <div className="grid grid-cols-1 gap-2">
          {company.phone && (
            <a href={`tel:${company.phone}`} className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors">
              <PhoneIcon className="w-4 h-4 shrink-0 text-primary" />
              {company.phone}
            </a>
          )}
          {company.email && (
            <a href={`mailto:${company.email}`} className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors">
              <MailIcon className="w-4 h-4 shrink-0 text-primary" />
              {company.email}
            </a>
          )}
          {company.website && (
            <a href={company.website} target="_blank" rel="noopener noreferrer" className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors">
              <GlobeIcon className="w-4 h-4 shrink-0 text-primary" />
              {company.website.replace(/^https?:\/\//, "")}
            </a>
          )}
          {!company.phone && !company.email && !company.website && (
            <p className="text-sm text-muted-foreground">{t("labels.no_contact", { ns: "common" })}</p>
          )}
        </div>
      </div>

      {/* Available Trips CTA */}
      <div className="p-4 rounded-xl bg-muted flex items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <CalendarIcon className="w-5 h-5 text-primary" />
          <div>
            <p className="text-sm font-semibold">{t("available_trips_cta", { ns: "traveler" })}</p>
            <p className="text-xs text-muted-foreground">{t("available_trips_cta_desc", { ns: "traveler" })}</p>
          </div>
        </div>
        <Link to={`/${lng}/traveler/search?companyId=${company._id}`}>
          <Button size="sm" className="shrink-0 cursor-pointer">{t("view_trips_btn", { ns: "traveler" })}</Button>
        </Link>
      </div>

      {/* Reviews section */}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-semibold flex items-center gap-1.5">
            <MessageSquareIcon className="w-4 h-4 text-primary" />
            {t("reviews.section_title", { ns: "traveler" })}
          </h3>
          {stats && stats.totalReviews > 0 && (
            <span className="text-xs text-muted-foreground">
              {stats.averageRating}/5 ({stats.totalReviews} {t("reviews.reviews_count", { ns: "traveler" })})
            </span>
          )}
        </div>

        {/* Rating distribution */}
        {stats && stats.totalReviews > 0 && (
          <div className="rounded-xl border p-4 space-y-2">
            <div className="flex items-center gap-3">
              <span className="text-3xl font-black text-foreground">{stats.averageRating}</span>
              <div>
                <StarRating rating={stats.averageRating} size="md" />
                <p className="text-xs text-muted-foreground mt-0.5">
                  {stats.totalReviews} {t("reviews.reviews_count", { ns: "traveler" })}
                </p>
              </div>
            </div>
            <div className="space-y-1.5 mt-2">
              {[5, 4, 3, 2, 1].map((star) => {
                const count = stats.distribution[star - 1];
                const percent = stats.totalReviews > 0 ? (count / stats.totalReviews) * 100 : 0;
                return (
                  <div key={star} className="flex items-center gap-2 text-xs">
                    <span className="w-3 text-muted-foreground">{star}</span>
                    <div className="flex-1 h-2 bg-muted rounded-full overflow-hidden">
                      <div
                        className="h-full bg-amber-400 rounded-full transition-all"
                        style={{ width: `${percent}%` }}
                      />
                    </div>
                    <span className="w-6 text-right text-muted-foreground">{count}</span>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Review cards */}
        {reviews && reviews.length > 0 ? (
          <div className="space-y-3">
            {reviews.map((review) => (
              <div key={review._id} className="rounded-xl border p-3 space-y-2">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <div className="w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center text-primary text-xs font-bold">
                      {review.travelerName.charAt(0).toUpperCase()}
                    </div>
                    <div>
                      <p className="text-xs font-semibold">{review.travelerName}</p>
                      {review.routeLabel && (
                        <p className="text-[10px] text-muted-foreground">{review.routeLabel}</p>
                      )}
                    </div>
                  </div>
                  <div className="text-right">
                    <StarRating rating={review.rating} size="sm" />
                    <p className="text-[10px] text-muted-foreground mt-0.5">
                      {formatDistanceToNow(new Date(review._creationTime), {
                        addSuffix: true,
                        locale: dateLocale,
                      })}
                    </p>
                  </div>
                </div>

                {review.comment && (
                  <p className="text-xs text-muted-foreground leading-relaxed">{review.comment}</p>
                )}

                {review.ownerReply && (
                  <div className="pl-3 border-l-2 border-primary/30 mt-2">
                    <p className="text-[10px] font-semibold text-primary">{t("reviews.owner_reply", { ns: "traveler" })}</p>
                    <p className="text-xs text-muted-foreground">{review.ownerReply}</p>
                  </div>
                )}
              </div>
            ))}

            {loadStatus === "CanLoadMore" && (
              <Button
                variant="ghost"
                size="sm"
                className="w-full cursor-pointer text-xs"
                onClick={() => loadMore(5)}
              >
                {t("buttons.load_more", { ns: "common" })}
              </Button>
            )}
          </div>
        ) : (
          <div className="text-center py-6 text-muted-foreground">
            <MessageSquareIcon className="w-8 h-8 mx-auto mb-2 opacity-30" />
            <p className="text-sm">{t("reviews.no_reviews", { ns: "traveler" })}</p>
          </div>
        )}
      </div>
    </div>
  );
}
