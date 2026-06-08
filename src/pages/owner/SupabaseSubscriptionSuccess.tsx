import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { CheckCircleIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";

export default function SupabaseSubscriptionSuccess() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();

  return (
    <div className="max-w-md mx-auto px-4 py-12">
      <Card className="text-center">
        <CardHeader>
          <div className="w-16 h-16 rounded-full bg-emerald-500/10 flex items-center justify-center mx-auto mb-2">
            <CheckCircleIcon className="w-8 h-8 text-emerald-600" />
          </div>
          <CardTitle>
            {t("subscription.success_title", { defaultValue: "Abonnement enregistré" })}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm text-muted-foreground">
            {t("subscription.success_desc", {
              defaultValue:
                "Votre abonnement a été pris en compte. Retournez à la console pour gérer votre compagnie.",
            })}
          </p>
          <Button asChild className="w-full">
            <Link to={`/${lng ?? "fr"}/owner`}>
              {t("subscription.back_console", { defaultValue: "Retour console" })}
            </Link>
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}
