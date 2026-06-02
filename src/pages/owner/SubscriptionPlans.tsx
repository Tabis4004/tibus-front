import { useState } from "react";
import { useQuery, useAction } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { useTranslation } from "react-i18next";
import { useParams } from "react-router-dom";
import {
  CheckIcon,
  ZapIcon,
  BuildingIcon,
  CreditCardIcon,
  XCircleIcon,
  AlertCircleIcon,
  ClockIcon,
  SparklesIcon,
  GiftIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog.tsx";
import { toast } from "sonner";
import { ConvexError } from "convex/values";
import { format, parseISO } from "date-fns";

const STATUS_STYLES: Record<string, { label: string; cls: string }> = {
  trial: { label: "Trial", cls: "bg-blue-500/10 text-blue-600 border-blue-500/30" },
  active: { label: "Active", cls: "bg-green-500/10 text-green-600 border-green-500/30" },
  past_due: { label: "Past Due", cls: "bg-yellow-500/10 text-yellow-600 border-yellow-500/30" },
  cancelled: { label: "Cancelled", cls: "bg-red-500/10 text-red-600 border-red-500/30" },
  expired: { label: "Expired", cls: "bg-red-500/10 text-red-600 border-red-500/30" },
  none: { label: "No Plan", cls: "bg-muted text-muted-foreground border-border" },
};

function formatDuration(days: number): string {
  if (days === 7) return "7 days";
  if (days === 30 || days === 31) return "1 month";
  if (days === 90 || days === 91) return "3 months";
  if (days === 180 || days === 182) return "6 months";
  if (days === 365 || days === 366) return "1 year";
  return `${days} days`;
}

function formatPrice(amount: number, currency: string): string {
  if (amount === 0) return "Free";
  return `${currency} ${amount.toLocaleString()}`;
}

export default function SubscriptionPlans() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const company = useQuery(api.companies.getMyCompany, {});
  const activePlans = useQuery(api.subscriptionPlans.listActive, {});
  const initSub = useAction(api.subscription.initializeSubscription);
  const cancelSub = useAction(api.subscription.cancelSubscription);

  const [loadingPlan, setLoadingPlan] = useState<string | null>(null);
  const [cancelDialogOpen, setCancelDialogOpen] = useState(false);
  const [cancelling, setCancelling] = useState(false);

  if (company === undefined || activePlans === undefined) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-8 space-y-4">
        <Skeleton className="h-8 w-48" />
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <Skeleton className="h-64 rounded-2xl" />
          <Skeleton className="h-64 rounded-2xl" />
        </div>
      </div>
    );
  }

  if (!company) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-16 text-center text-muted-foreground space-y-3">
        <BuildingIcon className="w-12 h-12 mx-auto opacity-30" />
        <p className="font-medium">{t("sub.no_company")}</p>
        <p className="text-sm">{t("sub.no_company_desc")}</p>
      </div>
    );
  }

  const currentStatus = company.subscriptionStatus ?? "none";
  const currentPlanId = company.subscriptionPlanId;
  const isActive = currentStatus === "active" || currentStatus === "trial";
  const statusStyle = STATUS_STYLES[currentStatus] ?? STATUS_STYLES.none;

  // Filter out the default trial plan from display (it's auto-assigned)
  const displayPlans = activePlans.filter((p) => !p.isDefault || p.price > 0);

  const handleSubscribe = async (planId: string) => {
    setLoadingPlan(planId);
    try {
      const result = await initSub({
        planId,
        successUrl: `${window.location.origin}/${lng}/owner/subscription/success?plan=${planId}`,
        cancelUrl: window.location.href,
      });
      window.open(result.url, "_blank");
    } catch (err) {
      if (err instanceof ConvexError) {
        const { message } = err.data as { message: string };
        toast.error(message);
      } else {
        toast.error(t("errors.generic", { ns: "common" }));
      }
    } finally {
      setLoadingPlan(null);
    }
  };

  const handleCancel = async () => {
    setCancelling(true);
    try {
      await cancelSub({});
      toast.success(t("sub.cancelled"));
      setCancelDialogOpen(false);
    } catch (err) {
      if (err instanceof ConvexError) {
        const { message } = err.data as { message: string };
        toast.error(message);
      } else {
        toast.error(t("errors.generic", { ns: "common" }));
      }
    } finally {
      setCancelling(false);
    }
  };

  // Find current plan details
  const currentPlanDetails = activePlans.find((p) => p._id === currentPlanId);

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-6">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">{t("sub.title")}</h1>
        <p className="text-muted-foreground text-sm mt-1">{t("sub.desc_new")}</p>
      </div>

      {/* Current subscription status */}
      <div className="rounded-xl border p-4 flex items-center justify-between gap-3">
        <div>
          <p className="text-sm font-semibold">{t("sub.current_plan")}</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            {isActive && company.planExpiresAt
              ? t("sub.expires", { date: format(parseISO(company.planExpiresAt), "MMM d, yyyy") })
              : currentStatus === "cancelled" || currentStatus === "expired"
              ? t("sub.expired_text")
              : t("sub.no_active")}
          </p>
          {currentPlanDetails && (
            <p className="text-xs text-primary font-medium mt-1">
              {currentPlanDetails.name} — {formatDuration(currentPlanDetails.durationDays)}
            </p>
          )}
        </div>
        <div className="flex items-center gap-2">
          <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full border text-xs font-medium ${statusStyle.cls}`}>
            {statusStyle.label}
          </span>
        </div>
      </div>

      {/* All features included notice */}
      <div className="rounded-xl bg-primary/5 border border-primary/20 p-4 flex items-start gap-3">
        <SparklesIcon className="w-4 h-4 text-primary shrink-0 mt-0.5" />
        <div className="text-sm space-y-1">
          <p className="font-medium text-foreground">{t("sub.all_features")}</p>
          <p className="text-xs text-muted-foreground">{t("sub.all_features_desc")}</p>
        </div>
      </div>

      {/* Plans */}
      {displayPlans.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {displayPlans.map((plan, index) => {
            const isCurrent = currentPlanId === plan._id && isActive;
            const isRecommended = index === Math.min(1, displayPlans.length - 1);

            return (
              <div
                key={plan._id}
                className={`rounded-2xl border-2 p-5 space-y-4 relative ${isCurrent ? "border-primary bg-primary/5" : isRecommended ? "border-primary" : "border-border"}`}
              >
                {isRecommended && !isCurrent && (
                  <div className="absolute -top-3 left-1/2 -translate-x-1/2">
                    <span className="bg-primary text-primary-foreground text-[10px] font-bold px-3 py-1 rounded-full">
                      {t("sub.recommended")}
                    </span>
                  </div>
                )}

                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <div className="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
                      <ClockIcon className="w-4 h-4 text-primary" />
                    </div>
                    <span className="font-bold">{plan.name}</span>
                  </div>
                  {isCurrent && (
                    <Badge className="text-[10px]">{t("sub.current")}</Badge>
                  )}
                </div>

                <div>
                  <span className="text-2xl font-extrabold">
                    {formatPrice(plan.price, plan.currency)}
                  </span>
                  <span className="text-muted-foreground text-sm ml-1">
                    / {formatDuration(plan.durationDays)}
                  </span>
                </div>

                <ul className="space-y-2">
                  <li className="flex items-center gap-2 text-sm">
                    <CheckIcon className="w-3.5 h-3.5 text-primary shrink-0" />
                    {t("sub.feat_all_features")}
                  </li>
                  <li className="flex items-center gap-2 text-sm">
                    <CheckIcon className="w-3.5 h-3.5 text-primary shrink-0" />
                    {t("sub.feat_duration", { days: plan.durationDays })}
                  </li>
                  <li className="flex items-center gap-2 text-sm">
                    <CheckIcon className="w-3.5 h-3.5 text-primary shrink-0" />
                    {t("sub.feat_support")}
                  </li>
                </ul>

                <Button
                  className="w-full cursor-pointer"
                  variant={isCurrent ? "secondary" : "default"}
                  disabled={isCurrent || loadingPlan !== null}
                  onClick={() => !isCurrent && handleSubscribe(plan._id)}
                >
                  {loadingPlan === plan._id ? (
                    t("sub.opening_checkout")
                  ) : isCurrent ? (
                    <><CheckIcon className="w-4 h-4 mr-1.5" /> {t("sub.current")}</>
                  ) : (
                    <><CreditCardIcon className="w-4 h-4 mr-1.5" /> {t("sub.subscribe_btn")}</>
                  )}
                </Button>
              </div>
            );
          })}
        </div>
      ) : (
        <div className="rounded-xl border border-dashed p-8 text-center text-muted-foreground space-y-2">
          <GiftIcon className="w-10 h-10 mx-auto opacity-40" />
          <p className="font-medium">{t("sub.no_plans")}</p>
          <p className="text-xs">{t("sub.no_plans_desc")}</p>
        </div>
      )}

      {/* Cancel option */}
      {isActive && currentStatus !== "trial" && (
        <div className="rounded-xl border border-dashed p-4 flex items-start gap-3">
          <AlertCircleIcon className="w-4 h-4 text-muted-foreground shrink-0 mt-0.5" />
          <div className="flex-1 space-y-2">
            <p className="text-sm font-medium">{t("sub.cancel_option")}</p>
            <p className="text-xs text-muted-foreground">{t("sub.cancel_option_desc")}</p>
            <button
              onClick={() => setCancelDialogOpen(true)}
              className="text-xs text-destructive hover:underline flex items-center gap-1 cursor-pointer"
            >
              <XCircleIcon className="w-3.5 h-3.5" /> {t("sub.cancel_my")}
            </button>
          </div>
        </div>
      )}

      {/* Payment info */}
      <div className="rounded-xl bg-muted/50 p-4 flex items-start gap-3">
        <ZapIcon className="w-4 h-4 text-primary shrink-0 mt-0.5" />
        <div className="text-xs text-muted-foreground space-y-1">
          <p className="font-medium text-foreground">{t("sub.payment_info")}</p>
          <p>{t("sub.payment_info_desc")}</p>
        </div>
      </div>

      {/* Cancel dialog */}
      <Dialog open={cancelDialogOpen} onOpenChange={setCancelDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t("sub.cancel_title")}</DialogTitle>
            <DialogDescription>{t("sub.cancel_desc")}</DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setCancelDialogOpen(false)} className="cursor-pointer">
              {t("sub.keep")}
            </Button>
            <Button variant="destructive" onClick={handleCancel} disabled={cancelling} className="cursor-pointer">
              {cancelling ? t("sub.cancelling") : t("sub.cancel_title")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
