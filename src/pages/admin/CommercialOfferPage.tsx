import { Link, Navigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ArrowLeftIcon, DownloadIcon, FileTextIcon } from "lucide-react";
import { useAppUser } from "@/hooks/use-app-user.ts";
import {
  canAccessCommercialOffer,
  COMMERCIAL_OFFER_FILENAME,
} from "@/lib/auth/commercial-offer-access.ts";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import commercialOfferUrl from "@/assets/downloads/offre-commerciale-tibus.docx?url";

export default function CommercialOfferPage() {
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("admin");
  const appUser = useAppUser();
  const locale = lng ?? "fr";
  const allowed = canAccessCommercialOffer(appUser.roles, appUser.isSuperAdmin);

  if (!appUser.isReady) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-10 space-y-4">
        <Skeleton className="h-10 w-64" />
        <Skeleton className="h-40 w-full" />
      </div>
    );
  }

  if (!allowed) {
    return <Navigate to={`/${locale}/admin`} replace />;
  }

  const handleDownload = () => {
    const anchor = document.createElement("a");
    anchor.href = commercialOfferUrl;
    anchor.download = COMMERCIAL_OFFER_FILENAME;
    anchor.rel = "noopener";
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
  };

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 pb-24 space-y-6">
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="icon" asChild>
          <Link to={`/${locale}/admin`}>
            <ArrowLeftIcon className="h-4 w-4" />
          </Link>
        </Button>
        <div className="flex-1 min-w-0">
          <h1 className="text-xl font-bold tracking-tight">
            {t("commercial_offer.title")}
          </h1>
          <p className="text-sm text-muted-foreground mt-1">{t("commercial_offer.subtitle")}</p>
        </div>
        <div className="hidden sm:flex w-11 h-11 rounded-xl bg-primary/10 items-center justify-center shrink-0">
          <FileTextIcon className="w-5 h-5 text-primary" />
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">{t("commercial_offer.card_title")}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm text-muted-foreground leading-relaxed">
            {t("commercial_offer.desc")}
          </p>
          <ul className="text-sm text-muted-foreground list-disc pl-5 space-y-1">
            <li>{t("commercial_offer.includes_letter")}</li>
            <li>{t("commercial_offer.includes_technical")}</li>
            <li>{t("commercial_offer.includes_financial")}</li>
          </ul>
          <Button type="button" className="gap-2 cursor-pointer" onClick={handleDownload}>
            <DownloadIcon className="w-4 h-4" />
            {t("commercial_offer.download")}
          </Button>
          <p className="text-xs text-muted-foreground italic">{t("commercial_offer.restricted")}</p>
        </CardContent>
      </Card>
    </div>
  );
}
