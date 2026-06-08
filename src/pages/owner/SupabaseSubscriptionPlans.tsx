import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { Link, useParams } from "react-router-dom";
import { CheckIcon, CreditCardIcon, SparklesIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import {
  getOwnerActiveSubscriptionSupabase,
  listOwnerSubscriptionPlansSupabase,
  type OwnerActiveSubscription,
  type OwnerSubscriptionPlan,
} from "@/lib/supabase/owner-subscription";
import { format, parseISO } from "date-fns";

function formatDuration(days: number): string {
  if (days === 7) return "7 jours";
  if (days === 30 || days === 31) return "1 mois";
  if (days === 90 || days === 91) return "3 mois";
  if (days === 365 || days === 366) return "1 an";
  return `${days} jours`;
}

export default function SupabaseSubscriptionPlans() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const { appUserId } = useSupabaseAuth();
  const [active, setActive] = useState<OwnerActiveSubscription | null | undefined>(undefined);
  const [plans, setPlans] = useState<OwnerSubscriptionPlan[] | undefined>(undefined);

  useEffect(() => {
    if (!appUserId) return;
    let cancelled = false;
    void Promise.all([
      getOwnerActiveSubscriptionSupabase(appUserId),
      listOwnerSubscriptionPlansSupabase(appUserId),
    ])
      .then(([sub, planList]) => {
        if (!cancelled) {
          setActive(sub);
          setPlans(planList);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setActive(null);
          setPlans([]);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [appUserId]);

  if (active === undefined || plans === undefined) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-8 space-y-4">
        <Skeleton className="h-8 w-56" />
        <Skeleton className="h-40 w-full rounded-xl" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-6">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">
          {t("subscription.title", { defaultValue: "Abonnement compagnie" })}
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          {t("subscription.desc", { defaultValue: "Plans disponibles pour votre pays." })}
        </p>
      </div>

      {active && (
        <Card className="border-primary/30">
          <CardHeader className="pb-2">
            <div className="flex items-center justify-between">
              <CardTitle className="text-base flex items-center gap-2">
                <SparklesIcon className="w-4 h-4 text-primary" />
                Abonnement actuel
              </CardTitle>
              <Badge variant={active.isActive ? "default" : "secondary"}>
                {active.isActive ? "Actif" : "Expiré"}
              </Badge>
            </div>
          </CardHeader>
          <CardContent className="text-sm space-y-1">
            <p>
              <span className="font-semibold">{active.planName}</span>
              {active.price != null && active.duration != null && (
                <span className="text-muted-foreground">
                  {" "}
                  · {active.price.toLocaleString()} / {formatDuration(active.duration)}
                </span>
              )}
            </p>
            <p className="text-muted-foreground">
              Fin : {format(parseISO(active.endDate), "dd MMM yyyy")}
            </p>
          </CardContent>
        </Card>
      )}

      {plans.length === 0 ? (
        <Card>
          <CardContent className="p-6 text-center text-sm text-muted-foreground">
            Aucun plan disponible pour votre pays. Contactez le support Tibus.
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-4">
          {plans.map((plan) => (
            <Card key={plan.id}>
              <CardHeader className="pb-2">
                <CardTitle className="text-lg">{plan.name}</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                {plan.features.length > 0 && (
                  <ul className="space-y-2">
                    {plan.features.map((feature) => (
                      <li key={feature} className="flex items-center gap-2 text-sm">
                        <CheckIcon className="w-4 h-4 text-primary shrink-0" />
                        {feature}
                      </li>
                    ))}
                  </ul>
                )}
                <div className="grid gap-2">
                  {plan.durations.map((duration) => (
                    <div
                      key={duration.id}
                      className="flex items-center justify-between rounded-lg border px-3 py-2 text-sm"
                    >
                      <span>{formatDuration(duration.duration)}</span>
                      <span className="font-semibold">
                        {duration.price === 0
                          ? "Gratuit"
                          : `${plan.currency} ${duration.price.toLocaleString()}`}
                      </span>
                    </div>
                  ))}
                </div>
                <Button className="w-full" variant="secondary" disabled>
                  <CreditCardIcon className="w-4 h-4 mr-2" />
                  Paiement en ligne — contactez le support
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <p className="text-xs text-center text-muted-foreground">
        Besoin d&apos;activer un plan ?{" "}
        <Link to={`/${lng ?? "fr"}/contact`} className="text-primary underline">
          Contactez Tibus
        </Link>
      </p>
    </div>
  );
}
