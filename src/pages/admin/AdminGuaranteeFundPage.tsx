import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { ArrowLeftIcon, LandmarkIcon, ShieldIcon } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { supabase } from "@/lib/supabase";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import GuaranteeFundManager from "./_components/GuaranteeFundManager.tsx";
import AdminAccessGate from "./_components/AdminAccessGate.tsx";
import AdminAuditHub from "./_components/AdminAuditHub.tsx";

type CompanyRow = {
  id: string;
  name: string;
  currency: string | null;
  countryName: string | null;
};

function joinedOne<T>(value: T | T[] | null | undefined): T | null {
  if (!value) return null;
  return Array.isArray(value) ? value[0] ?? null : value;
}

export default function AdminGuaranteeFundPage() {
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const appUser = useAppUser();
  const [companies, setCompanies] = useState<CompanyRow[] | undefined>(undefined);

  const canAccess = appUser.isSuperAdmin || appUser.roles.includes("admin_pays");

  useEffect(() => {
    if (!appUser.isReady) return;
    if (!canAccess) {
      navigate(`/${lng ?? "fr"}`, { replace: true });
      return;
    }

    let cancelled = false;
    void supabase
      .from("Companies")
      .select("id, name, Countries(name, currency)")
      .order("name")
      .then(({ data, error }) => {
        if (cancelled) return;
        if (error) {
          setCompanies([]);
          return;
        }
        setCompanies(
          (data ?? []).map((row) => {
            const country = joinedOne(
              row.Countries as { name: string; currency: string | null } | { name: string; currency: string | null }[],
            );
            return {
              id: row.id as string,
              name: row.name as string,
              currency: country?.currency ?? null,
              countryName: country?.name ?? null,
            };
          }),
        );
      });

    return () => {
      cancelled = true;
    };
  }, [appUser.isReady, canAccess, navigate, lng]);

  if (!appUser.isReady || companies === undefined) {
    return (
      <div className="max-w-6xl mx-auto px-4 py-8">
        <Skeleton className="h-10 w-64 mb-6" />
        <Skeleton className="h-96 w-full" />
      </div>
    );
  }

  return (
    <AdminAccessGate>
    <div className="max-w-6xl mx-auto px-4 py-8 space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center">
            <LandmarkIcon className="w-5 h-5 text-primary" />
          </div>
          <div>
            <h1 className="text-xl font-extrabold tracking-tight">
              {t("guarantee_fund.title", { defaultValue: "Fond de garantie" })}
            </h1>
            <p className="text-sm text-muted-foreground">
              {t("guarantee_fund.desc", {
                defaultValue:
                  "Soumettre des dépôts plateforme et suivre les mouvements en temps réel.",
              })}
            </p>
          </div>
        </div>
        <div className="flex gap-2">
          <Link to={`/${lng}/admin`}>
            <Button variant="outline" size="sm" className="gap-2 cursor-pointer">
              <ShieldIcon className="w-4 h-4" />
              Admin
            </Button>
          </Link>
          <Link to={`/${lng}`}>
            <Button variant="ghost" size="sm" className="gap-2 cursor-pointer">
              <ArrowLeftIcon className="w-4 h-4" />
              {tc("buttons.back", { defaultValue: "Retour" })}
            </Button>
          </Link>
        </div>
      </div>

      <GuaranteeFundManager companies={companies} />
      <AdminAuditHub moduleKey="admin.guarantee_fund" scopeLabel="guarantee_fund" />
    </div>
    </AdminAccessGate>
  );
}
