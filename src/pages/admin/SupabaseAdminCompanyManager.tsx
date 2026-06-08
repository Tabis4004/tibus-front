import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import {
  ArrowLeftIcon,
  BuildingIcon,
  BusIcon,
  MapPinIcon,
  UsersIcon,
  RouteIcon,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { supabase } from "@/lib/supabase";
import { useAppUser } from "@/hooks/use-app-user";

type CompanyOverview = {
  id: string;
  name: string;
  managerName: string | null;
  isActive: boolean;
  countryName: string | null;
  busCount: number;
  stationCount: number;
  sellerCount: number;
};

export default function SupabaseAdminCompanyManager() {
  const { lng, companyId } = useParams<{ lng: string; companyId: string }>();
  const navigate = useNavigate();
  const { t } = useTranslation("common");
  const { isSuperAdmin, isReady } = useAppUser();
  const [company, setCompany] = useState<CompanyOverview | null | undefined>(undefined);

  useEffect(() => {
    if (isReady && !isSuperAdmin) {
      navigate(`/${lng ?? "fr"}`, { replace: true });
    }
  }, [isReady, isSuperAdmin, lng, navigate]);

  useEffect(() => {
    if (!companyId) return;
    let cancelled = false;

    void (async () => {
      const { data: row, error } = await supabase
        .from("Companies")
        .select("id, name, managerName, isActive, Countries(name)")
        .eq("id", companyId)
        .maybeSingle();

      if (error || !row) {
        if (!cancelled) setCompany(null);
        return;
      }

      const country = Array.isArray(row.Countries) ? row.Countries[0] : row.Countries;

      const [{ count: busCount }, { count: stationCount }, { data: roles }] = await Promise.all([
        supabase.from("Bus").select("id", { count: "exact", head: true }).eq("companyId", companyId),
        supabase.from("Gares").select("id", { count: "exact", head: true }).eq("companyId", companyId),
        supabase
          .from("UserRoles")
          .select("Role(name)")
          .eq("companyId", companyId),
      ]);

      const sellerCount = (roles ?? []).filter((r) => {
        const role = Array.isArray(r.Role) ? r.Role[0] : r.Role;
        const name = (role as { name?: string } | null)?.name;
        return name === "vendeur" || name === "controleur" || name === "comptable_compagnie";
      }).length;

      if (!cancelled) {
        setCompany({
          id: row.id as string,
          name: row.name as string,
          managerName: (row.managerName as string | null) ?? null,
          isActive: Boolean(row.isActive),
          countryName: (country as { name?: string } | null)?.name ?? null,
          busCount: busCount ?? 0,
          stationCount: stationCount ?? 0,
          sellerCount,
        });
      }
    })().catch(() => {
      if (!cancelled) setCompany(null);
    });

    return () => {
      cancelled = true;
    };
  }, [companyId]);

  if (!companyId) return null;

  if (company === undefined) {
    return (
      <div className="max-w-4xl mx-auto px-4 py-8 space-y-6">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }

  if (!company) {
    return (
      <div className="max-w-4xl mx-auto px-4 py-16 text-center text-muted-foreground">
        Compagnie introuvable
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto px-4 py-6 space-y-6">
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="sm" asChild>
          <Link to={`/${lng ?? "fr"}/admin`}>
            <ArrowLeftIcon className="w-4 h-4 mr-1" />
            Admin
          </Link>
        </Button>
        <div>
          <h1 className="text-xl font-extrabold flex items-center gap-2">
            <BuildingIcon className="w-5 h-5 text-primary" />
            {company.name}
          </h1>
          <p className="text-sm text-muted-foreground">
            {company.managerName ?? "—"} · {company.countryName ?? "—"}
          </p>
        </div>
        <Badge variant={company.isActive ? "default" : "secondary"} className="ml-auto">
          {company.isActive ? t("status.active") : t("status.inactive")}
        </Badge>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <BusIcon className="w-4 h-4" /> Bus
            </CardTitle>
          </CardHeader>
          <CardContent className="text-2xl font-bold">{company.busCount}</CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <MapPinIcon className="w-4 h-4" /> Gares
            </CardTitle>
          </CardHeader>
          <CardContent className="text-2xl font-bold">{company.stationCount}</CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <UsersIcon className="w-4 h-4" /> Équipe
            </CardTitle>
          </CardHeader>
          <CardContent className="text-2xl font-bold">{company.sellerCount}</CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <RouteIcon className="w-4 h-4" />
            Gestion avancée
          </CardTitle>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground space-y-3">
          <p>
            La gestion opérationnelle (gares, bus, trajets, vendeurs) se fait depuis la console
            owner avec un compte assigné à cette compagnie.
          </p>
          <p>
            Utilisez le panneau admin pour créer des utilisateurs, assigner le rôle owner et lier
            la compagnie <span className="font-semibold text-foreground">{company.name}</span>.
          </p>
          <Button asChild variant="secondary">
            <Link to={`/${lng ?? "fr"}/admin`}>Retour panneau admin</Link>
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}
