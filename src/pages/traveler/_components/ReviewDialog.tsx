import { useState } from "react";
import { useMutation } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import StarRating from "@/components/ui/star-rating.tsx";
import { toast } from "sonner";
import { ConvexError } from "convex/values";
import { useTranslation } from "react-i18next";

type ReviewDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  bookingId: Id<"bookings">;
  routeLabel?: string;
};

export default function ReviewDialog({ open, onOpenChange, bookingId, routeLabel }: ReviewDialogProps) {
  const { t } = useTranslation("traveler");
  const submitReview = useMutation(api.reviews.submitReview);
  const [rating, setRating] = useState(0);
  const [comment, setComment] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async () => {
    if (rating === 0) {
      toast.error(t("reviews.select_rating"));
      return;
    }
    setSubmitting(true);
    try {
      await submitReview({
        bookingId,
        rating,
        comment: comment.trim() || undefined,
      });
      toast.success(t("reviews.submitted"));
      onOpenChange(false);
      setRating(0);
      setComment("");
    } catch (err) {
      if (err instanceof ConvexError) {
        const { message } = err.data as { message: string };
        toast.error(message);
      } else {
        toast.error(t("errors.generic", { ns: "common" }));
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("reviews.title")}</DialogTitle>
          <DialogDescription>
            {routeLabel
              ? t("reviews.rate_trip", { route: routeLabel })
              : t("reviews.rate_desc")}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-2">
          {/* Star rating */}
          <div className="flex flex-col items-center gap-2">
            <StarRating
              rating={rating}
              size="lg"
              interactive
              onChange={setRating}
            />
            <span className="text-xs text-muted-foreground">
              {rating > 0
                ? t(`reviews.rating_${rating}`)
                : t("reviews.tap_to_rate")}
            </span>
          </div>

          {/* Comment */}
          <Textarea
            placeholder={t("reviews.comment_placeholder")}
            value={comment}
            onChange={(e) => setComment(e.target.value)}
            rows={3}
            maxLength={500}
            className="resize-none"
          />
          <p className="text-[10px] text-muted-foreground text-right">
            {comment.length}/500
          </p>
        </div>

        <DialogFooter>
          <Button
            variant="ghost"
            onClick={() => onOpenChange(false)}
            className="cursor-pointer"
          >
            {t("buttons.cancel", { ns: "common" })}
          </Button>
          <Button
            onClick={handleSubmit}
            disabled={submitting || rating === 0}
            className="cursor-pointer"
          >
            {submitting ? t("reviews.submitting") : t("reviews.submit")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
