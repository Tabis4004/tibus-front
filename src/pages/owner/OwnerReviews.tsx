import { useState } from "react";
import { usePaginatedQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import { MessageSquareIcon, ReplyIcon, StarIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription } from "@/components/ui/empty.tsx";
import StarRating from "@/components/ui/star-rating.tsx";
import { useTranslation } from "react-i18next";
import { formatDistanceToNow } from "date-fns";
import { fr, enUS } from "date-fns/locale";
import { useParams } from "react-router-dom";
import { toast } from "sonner";
import { ConvexError } from "convex/values";

export default function OwnerReviews() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const dateLocale = lng === "fr" ? fr : enUS;

  const { results, status, loadMore } = usePaginatedQuery(
    api.reviews.listForOwner,
    {},
    { initialNumItems: 10 }
  );
  const replyToReview = useMutation(api.reviews.replyToReview);

  const [replyingTo, setReplyingTo] = useState<Id<"reviews"> | null>(null);
  const [replyText, setReplyText] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const handleReply = async (reviewId: Id<"reviews">) => {
    if (!replyText.trim()) return;
    setSubmitting(true);
    try {
      await replyToReview({ reviewId, reply: replyText.trim() });
      toast.success(t("reviews.reply_sent"));
      setReplyingTo(null);
      setReplyText("");
    } catch (err) {
      if (err instanceof ConvexError) {
        const { message } = err.data as { message: string };
        toast.error(message);
      } else {
        toast.error(t("reviews.reply_error"));
      }
    } finally {
      setSubmitting(false);
    }
  };

  if (results === undefined) {
    return (
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-extrabold tracking-tight">{t("reviews.title")}</h1>
            <p className="text-sm text-muted-foreground mt-1">{t("reviews.desc")}</p>
          </div>
        </div>
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-32 w-full rounded-xl" />
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">{t("reviews.title")}</h1>
        <p className="text-sm text-muted-foreground mt-1">{t("reviews.desc")}</p>
      </div>

      {results.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon"><MessageSquareIcon /></EmptyMedia>
            <EmptyTitle>{t("reviews.no_reviews")}</EmptyTitle>
            <EmptyDescription>{t("reviews.no_reviews_desc")}</EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <div className="space-y-3">
          {results.map((review) => (
            <div key={review._id} className="rounded-xl border p-4 space-y-3">
              {/* Header */}
              <div className="flex items-start justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-9 h-9 rounded-full bg-primary/10 flex items-center justify-center text-primary font-bold text-sm">
                    {review.travelerName.charAt(0).toUpperCase()}
                  </div>
                  <div>
                    <p className="text-sm font-semibold">{review.travelerName}</p>
                    <p className="text-xs text-muted-foreground">{review.travelerEmail ?? ""}</p>
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

              {/* Route info */}
              {review.routeLabel && (
                <p className="text-xs text-muted-foreground">
                  {review.routeLabel}
                  {review.departureTime && ` — ${new Date(review.departureTime).toLocaleDateString()}`}
                </p>
              )}

              {/* Comment */}
              {review.comment && (
                <p className="text-sm text-foreground leading-relaxed">{review.comment}</p>
              )}

              {/* Owner reply or reply form */}
              {review.ownerReply ? (
                <div className="pl-3 border-l-2 border-primary/30 bg-muted/30 rounded-r-lg p-2">
                  <p className="text-[10px] font-semibold text-primary mb-0.5">
                    {t("reviews.your_reply")}
                  </p>
                  <p className="text-xs text-muted-foreground">{review.ownerReply}</p>
                </div>
              ) : replyingTo === review._id ? (
                <div className="space-y-2 pl-3 border-l-2 border-primary/30">
                  <Textarea
                    value={replyText}
                    onChange={(e) => setReplyText(e.target.value)}
                    placeholder={t("reviews.reply_placeholder")}
                    rows={2}
                    className="resize-none text-sm"
                    maxLength={300}
                  />
                  <div className="flex items-center gap-2">
                    <Button
                      size="sm"
                      className="h-7 text-xs cursor-pointer"
                      onClick={() => handleReply(review._id)}
                      disabled={submitting || !replyText.trim()}
                    >
                      {submitting ? t("reviews.sending") : t("reviews.send_reply")}
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      className="h-7 text-xs cursor-pointer"
                      onClick={() => { setReplyingTo(null); setReplyText(""); }}
                    >
                      {t("buttons.cancel", { ns: "common" })}
                    </Button>
                  </div>
                </div>
              ) : (
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-7 text-xs cursor-pointer gap-1"
                  onClick={() => setReplyingTo(review._id)}
                >
                  <ReplyIcon className="w-3 h-3" /> {t("reviews.reply")}
                </Button>
              )}
            </div>
          ))}

          {status === "CanLoadMore" && (
            <Button
              variant="ghost"
              size="sm"
              className="w-full cursor-pointer text-xs"
              onClick={() => loadMore(10)}
            >
              {t("buttons.load_more", { ns: "common" })}
            </Button>
          )}
        </div>
      )}
    </div>
  );
}
