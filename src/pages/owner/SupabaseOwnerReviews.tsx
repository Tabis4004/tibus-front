import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useParams } from "react-router-dom";
import { formatDistanceToNow } from "date-fns";
import { fr, enUS } from "date-fns/locale";
import { MessageSquareIcon, ReplyIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Empty,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
  EmptyDescription,
} from "@/components/ui/empty.tsx";
import StarRating from "@/components/ui/star-rating.tsx";
import { toast } from "sonner";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useOwnerCompany, OWNER_COMPANY_REFRESH_EVENT } from "@/hooks/use-owner-company.tsx";
import {
  listOwnerReviewsSupabase,
  replyToReviewSupabase,
  type OwnerReviewRow,
} from "@/lib/supabase/reviews";

export default function SupabaseOwnerReviews() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const { appUserId } = useSupabaseAuth();
  const { companyId } = useOwnerCompany();
  const dateLocale = lng === "fr" ? fr : enUS;
  const [reviews, setReviews] = useState<OwnerReviewRow[] | undefined>(undefined);
  const [replyingTo, setReplyingTo] = useState<string | null>(null);
  const [replyText, setReplyText] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const loadReviews = useCallback(async () => {
    if (!appUserId || !companyId) return;
    setReviews(undefined);
    try {
      setReviews(await listOwnerReviewsSupabase(appUserId, companyId));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("reviews.reply_error"));
      setReviews([]);
    }
  }, [appUserId, companyId, t]);

  useEffect(() => {
    void loadReviews();
  }, [loadReviews]);

  useEffect(() => {
    const onRefresh = () => void loadReviews();
    window.addEventListener(OWNER_COMPANY_REFRESH_EVENT, onRefresh);
    return () => window.removeEventListener(OWNER_COMPANY_REFRESH_EVENT, onRefresh);
  }, [loadReviews]);

  const handleReply = async (reviewId: string) => {
    if (!replyText.trim()) return;
    setSubmitting(true);
    try {
      await replyToReviewSupabase(reviewId, replyText.trim());
      toast.success(t("reviews.reply_sent"));
      setReplyingTo(null);
      setReplyText("");
      void loadReviews();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("reviews.reply_error"));
    } finally {
      setSubmitting(false);
    }
  };

  if (reviews === undefined) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-4">
        <Skeleton className="h-8 w-48" />
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-32 w-full rounded-xl" />
        ))}
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">{t("reviews.title")}</h1>
        <p className="text-sm text-muted-foreground mt-1">{t("reviews.desc")}</p>
      </div>

      {reviews.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <MessageSquareIcon />
            </EmptyMedia>
            <EmptyTitle>{t("reviews.no_reviews")}</EmptyTitle>
            <EmptyDescription>{t("reviews.no_reviews_desc")}</EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <div className="space-y-4">
          {reviews.map((review) => (
            <div key={review.id} className="rounded-xl border p-4 space-y-3">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="font-semibold text-sm">{review.travelerName}</p>
                  <StarRating rating={review.rating} size="sm" />
                </div>
                <span className="text-[10px] text-muted-foreground shrink-0">
                  {formatDistanceToNow(new Date(review.createdAt), {
                    addSuffix: true,
                    locale: dateLocale,
                  })}
                </span>
              </div>
              {review.comment && (
                <p className="text-sm text-muted-foreground">{review.comment}</p>
              )}
              {review.ownerReply ? (
                <div className="rounded-lg bg-muted p-3 text-sm">
                  <p className="text-xs font-semibold mb-1">{t("reviews.your_reply")}</p>
                  {review.ownerReply}
                </div>
              ) : replyingTo === review.id ? (
                <div className="space-y-2">
                  <Textarea
                    value={replyText}
                    onChange={(e) => setReplyText(e.target.value)}
                    placeholder={t("reviews.reply_placeholder")}
                    rows={3}
                  />
                  <div className="flex gap-2">
                    <Button
                      size="sm"
                      onClick={() => handleReply(review.id)}
                      disabled={submitting || !replyText.trim()}
                    >
                      {t("reviews.send_reply")}
                    </Button>
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() => {
                        setReplyingTo(null);
                        setReplyText("");
                      }}
                    >
                      {t("buttons.cancel", { ns: "common" })}
                    </Button>
                  </div>
                </div>
              ) : (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => setReplyingTo(review.id)}
                >
                  <ReplyIcon className="w-3.5 h-3.5 mr-1.5" />
                  {t("reviews.reply_btn")}
                </Button>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
