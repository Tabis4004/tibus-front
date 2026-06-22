import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { CalendarIcon, MapPinIcon, ScanLineIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { roleDashboardPath } from "@/lib/gare-role-routing.ts";

export default function CompanyControleurDashboardPage() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const locale = lng ?? "fr";

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">
          {t("controleur.dashboard_title", { defaultValue: "Contrôle compagnie" })}
        </h1>
        <p className="text-muted-foreground text-sm mt-1">
          {t("controleur.dashboard_desc", {
            defaultValue: "Scanner les billets et suivre les départs de la compagnie.",
          })}
        </p>
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        <Button asChild variant="outline" className="h-auto py-4 justify-start">
          <Link to={`/${locale}/verify/scan`}>
            <ScanLineIcon className="w-4 h-4 mr-2 shrink-0" />
            {t("controleur.link_scan", { defaultValue: "Scanner les billets" })}
          </Link>
        </Button>
        <Button asChild variant="outline" className="h-auto py-4 justify-start">
          <Link to={`/${locale}/owner/trips`}>
            <CalendarIcon className="w-4 h-4 mr-2 shrink-0" />
            {t("controleur.link_trips", { defaultValue: "Voyages & départs" })}
          </Link>
        </Button>
      </div>

      <Card>
        <CardContent className="p-4 text-sm text-muted-foreground flex items-start gap-2">
          <MapPinIcon className="w-4 h-4 shrink-0 mt-0.5" />
          {t("controleur.dashboard_hint", {
            defaultValue:
              "Ce tableau de bord est réservé au rôle contrôleur compagnie. Pour une gare précise, utilisez le dashboard contrôleur gare.",
          })}
        </CardContent>
      </Card>
    </div>
  );
}
