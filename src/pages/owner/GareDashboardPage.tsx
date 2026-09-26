import { useEffect, useState } from "react";
import { Link, Navigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { CalendarIcon, RouteIcon, MapPinIcon, ScanLineIcon } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import {
  isGareCashValidatorRole,
  isGareManagerRole,
} from "@/lib/owner-team-roles.ts";
import { roleDashboardPath } from "@/lib/gare-role-routing.ts";
import { resolveUserGareIdSupabase } from "@/lib/supabase/gare-team.ts";
import { supabase } from "@/lib/supabase";
import GareTeamPanel from "./_components/GareTeamPanel.tsx";
import CounterCommissionTiersPanel from "./_components/CounterCommissionTiersPanel.tsx";
import StationCashReversalsPanel from "@/pages/company/_components/StationCashReversalsPanel.tsx";

export type GareDashboardVariant = "gerant" | "comptable" | "controleur";

type GareSummary = {
  id: string;
  name: string;
  city: string | null;
  companyId: string | null;
};

function canAccessVariant(
  variant: GareDashboardVariant,
  roles: readonly string[],
): boolean {
  if (roles.includes("owner") || roles.includes("super_admin")) return true;
  if (variant === "gerant") return roles.some((role) => isGareManagerRole(role));
  if (variant === "comptable") return roles.some((role) => isGareCashValidatorRole(role));
  if (variant === "controleur") return roles.includes("controleur_gare");
  return false;
}

export default function GareDashboardPage({ variant }: { variant: GareDashboardVariant }) {
  const { t } = useTranslation("owner");
  const { lng, gareId: routeGareId } = useParams<{ lng: string; gareId?: string }>();
  const locale = lng ?? "fr";
  const { companyId: ownerCompanyId, selectedCompany } = useOwnerCompany();
  const appUser = useAppUser();
  const [gare, setGare] = useState<GareSummary | null | undefined>(undefined);
  // La compagnie qui compte pour cette page est TOUJOURS celle propriétaire
  // de la gare affichée (gare.companyId) — jamais celle du sélecteur en haut
  // (ownerCompanyId). Les deux ne coïncidaient que par hasard : un owner qui
  // change de compagnie dans le sélecteur voyait companyId changer alors que
  // `gare` restait la même (sa gare personnelle, résolue une fois pour
  // toutes via resolveUserGareIdSupabase) — les panneaux enfants recevaient
  // alors un companyId qui ne correspondait plus à la gare réellement
  // affichée. Voir aussi la vérification de cohérence juste avant le rendu.
  const companyId = gare?.companyId ?? null;

  // Owner et super_admin voient tout le tableau de bord gérant (équipe,
  // commissions, reversements) même sans rôle gerant_gare explicite — sinon
  // ils accèdent à la page (canAccessVariant) mais avec des blocs masqués.
  const isOwnerLike =
    appUser.roles.includes("owner") || appUser.roles.includes("super_admin");
  const canManageTeam =
    isOwnerLike || appUser.roles.some((role) => isGareManagerRole(role));
  const canValidateCash =
    isOwnerLike || appUser.roles.some((role) => isGareCashValidatorRole(role));
  const allowed = canAccessVariant(variant, appUser.roles);

  useEffect(() => {
    let cancelled = false;

    // Un gareId explicite dans l'URL (venu de "Gérer" dans la liste des
    // gares) n'est honoré que pour un owner/super_admin — pour un staff gare
    // (gerant_gare, comptable_gare...), le rôle en base n'est pas garanti
    // scoping à CETTE gare précise ; on continue donc à résoudre uniquement
    // sa propre gare via resolveUserGareIdSupabase, comme avant.
    const useRouteGareId = Boolean(routeGareId) && isOwnerLike;

    void (async () => {
      try {
        const gareId = useRouteGareId ? routeGareId! : await resolveUserGareIdSupabase();
        if (cancelled) return;
        if (!gareId) {
          setGare(null);
          return;
        }

        const { data, error } = await supabase
          .from("Gares")
          .select("id, name, companyId, Cities(name)")
          .eq("id", gareId)
          .maybeSingle();

        if (error) throw error;
        if (!data) {
          setGare(null);
          return;
        }

        const cityJoin = data.Cities as { name: string } | { name: string }[] | null;
        const cityName = Array.isArray(cityJoin) ? cityJoin[0]?.name : cityJoin?.name;

        setGare({
          id: data.id as string,
          name: data.name as string,
          city: cityName ?? null,
          companyId: (data.companyId as string | null) ?? null,
        });
      } catch (err) {
        if (!cancelled) {
          toast.error(err instanceof Error ? err.message : t("gare.load_error"));
          setGare(null);
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [t, routeGareId, isOwnerLike]);

  if (!appUser.isReady) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-4">
        <Skeleton className="h-10 w-56" />
        <Skeleton className="h-28 w-full rounded-xl" />
      </div>
    );
  }

  if (!allowed) {
    return <Navigate to={`/${locale}`} replace />;
  }

  if (gare === undefined) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-4">
        <Skeleton className="h-10 w-56" />
        <Skeleton className="h-28 w-full rounded-xl" />
        <Skeleton className="h-40 w-full rounded-xl" />
      </div>
    );
  }

  if (!gare || !companyId) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-6">
        <Card>
          <CardContent className="p-6 text-sm text-muted-foreground">{t("gare.no_gare")}</CardContent>
        </Card>
      </div>
    );
  }

  const titleKey =
    variant === "comptable"
      ? "gare.comptable_dashboard_title"
      : variant === "controleur"
        ? "gare.controleur_dashboard_title"
        : "gare.gerant_dashboard_title";

  const titleDefault =
    variant === "comptable"
      ? "Comptabilité gare"
      : variant === "controleur"
        ? "Contrôle gare"
        : "Ma gare (gérant)";

  const descKey =
    variant === "comptable"
      ? "gare.comptable_dashboard_desc"
      : variant === "controleur"
        ? "gare.controleur_dashboard_desc"
        : "gare.gerant_dashboard_desc";

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">
          {t(titleKey, { defaultValue: titleDefault })}
        </h1>
        <p className="text-muted-foreground text-sm mt-0.5 flex items-center gap-1.5">
          <MapPinIcon className="w-3.5 h-3.5" />
          {gare.name}
          {gare.city ? ` · ${gare.city}` : ""}
        </p>
        <p className="text-xs text-muted-foreground mt-1">
          {t(descKey, {
            defaultValue:
              variant === "comptable"
                ? "Validez les reversements caisse de cette gare."
                : variant === "controleur"
                  ? "Contrôlez l'embarquement pour votre gare."
                  : "Équipe, commissions guichet et programmation des départs.",
          })}
        </p>
        {isOwnerLike && ownerCompanyId && companyId && ownerCompanyId !== companyId ? (
          <p className="text-xs mt-2 rounded-md bg-amber-50 text-amber-800 border border-amber-200 px-2.5 py-1.5 dark:bg-amber-950/40 dark:text-amber-300 dark:border-amber-900">
            {t("gare.other_company_notice", {
              defaultValue:
                `Cette gare n'appartient pas à ${selectedCompany?.name ?? "la compagnie sélectionnée"} ci-dessus` +
                (routeGareId ? " — normal, tu l'as ouverte directement depuis la liste des gares." : "."),
            })}
          </p>
        ) : null}
      </div>

      {variant === "gerant" && canManageTeam ? (
        <div className="grid gap-3 sm:grid-cols-2">
          <Button asChild variant="outline" className="h-auto py-4 justify-start">
            <Link to={`/${locale}/owner/trips`}>
              <CalendarIcon className="w-4 h-4 mr-2 shrink-0" />
              {t("gare.link_trips")}
            </Link>
          </Button>
          <Button asChild variant="outline" className="h-auto py-4 justify-start">
            <Link to={`/${locale}/owner/routes`}>
              <RouteIcon className="w-4 h-4 mr-2 shrink-0" />
              {t("gare.link_routes")}
            </Link>
          </Button>
        </div>
      ) : null}

      {variant === "controleur" ? (
        <Button asChild className="h-auto py-4 justify-start w-full sm:w-auto">
          <Link to={`/${locale}/verify/scan`}>
            <ScanLineIcon className="w-4 h-4 mr-2 shrink-0" />
            {t("gare.controleur_link_scan", { defaultValue: "Ouvrir le scanner QR" })}
          </Link>
        </Button>
      ) : null}

      {variant === "comptable" && canValidateCash ? (
        <StationCashReversalsPanel
          companyId={companyId}
          gareId={gare.id}
          canValidate={canValidateCash}
        />
      ) : null}

      {variant === "gerant" && canValidateCash ? (
        <StationCashReversalsPanel
          companyId={companyId}
          gareId={gare.id}
          canValidate={canValidateCash}
        />
      ) : null}

      {variant === "gerant" && canManageTeam ? <GareTeamPanel gareId={gare.id} /> : null}
      {variant === "gerant" && canManageTeam ? (
        <CounterCommissionTiersPanel companyId={companyId} gareId={gare.id} />
      ) : null}

      {variant === "comptable" && appUser.roles.includes("gerant_gare") ? (
        <p className="text-xs text-muted-foreground">
          {t("gare.also_gerant_link", {
            defaultValue: "Vous êtes aussi gérant :",
          })}{" "}
          <Link to={roleDashboardPath(locale, "gerant_gare")} className="underline">
            {t("gare.gerant_dashboard_title", { defaultValue: "Ma gare (gérant)" })}
          </Link>
        </p>
      ) : null}
    </div>
  );
}
