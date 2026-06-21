import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { CalendarIcon, RouteIcon, MapPinIcon } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { isGareManagerRole } from "@/lib/owner-team-roles.ts";
import { resolveManagedGareIdSupabase } from "@/lib/supabase/gare-team.ts";
import { supabase } from "@/lib/supabase";
import GareTeamPanel from "./_components/GareTeamPanel.tsx";
import CounterCommissionTiersPanel from "./_components/CounterCommissionTiersPanel.tsx";

type GareSummary = {
  id: string;
  name: string;
  city: string | null;
};

export default function GareDashboardPage() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const locale = lng ?? "fr";
  const { companyId } = useOwnerCompany();
  const appUser = useAppUser();
  const [gare, setGare] = useState<GareSummary | null | undefined>(undefined);

  const canManageTeam = appUser.roles.some((role) => isGareManagerRole(role));

  useEffect(() => {
    let cancelled = false;

    void (async () => {
      try {
        const gareId = await resolveManagedGareIdSupabase();
        if (cancelled) return;
        if (!gareId) {
          setGare(null);
          return;
        }

        const { data, error } = await supabase
          .from("Gares")
          .select("id, name, Cities(name)")
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
  }, [t]);

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

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">{t("gare.dashboard_title")}</h1>
        <p className="text-muted-foreground text-sm mt-0.5 flex items-center gap-1.5">
          <MapPinIcon className="w-3.5 h-3.5" />
          {gare.name}
          {gare.city ? ` · ${gare.city}` : ""}
        </p>
      </div>

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

      {canManageTeam ? <GareTeamPanel gareId={gare.id} /> : null}
      {canManageTeam ? (
        <CounterCommissionTiersPanel companyId={companyId} gareId={gare.id} />
      ) : null}
    </div>
  );
}
