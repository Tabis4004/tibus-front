import { useEffect, useState } from "react";
import { Link, Navigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ArrowLeftIcon } from "lucide-react";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { canAccessCommercialOffer } from "@/lib/auth/commercial-offer-access.ts";
import { supabase } from "@/lib/supabase";
import { resolveAdminPaysCountryIdSupabase } from "@/lib/supabase/commercial-offer-customization.ts";
import CommercialOfferDocumentPanel from "./_components/CommercialOfferDocumentPanel.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";

type CountryOption = { id: string; name: string };

export default function CommercialOfferPage() {
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("admin");
  const appUser = useAppUser();
  const locale = lng ?? "fr";
  const allowed = canAccessCommercialOffer(appUser.roles, appUser.isSuperAdmin);
  const [countries, setCountries] = useState<CountryOption[]>([]);
  const [countryId, setCountryId] = useState<string | null>(null);
  const [countryName, setCountryName] = useState<string | null>(null);
  const [bootstrapping, setBootstrapping] = useState(true);

  useEffect(() => {
    if (!appUser.isReady || !allowed) {
      setBootstrapping(false);
      return;
    }

    let cancelled = false;
    void (async () => {
      try {
        if (appUser.isSuperAdmin) {
          const { data, error } = await supabase.from("Countries").select("id, name").order("name");
          if (error) throw error;
          const rows = (data ?? []) as CountryOption[];
          if (!cancelled) {
            setCountries(rows);
            setCountryId((current) => current ?? rows[0]?.id ?? null);
          }
          return;
        }

        const adminCountryId =
          (await resolveAdminPaysCountryIdSupabase(appUser.profile?.id ?? ""))
          ?? appUser.profile?.countryId
          ?? null;
        if (!cancelled) {
          setCountryId(adminCountryId);
        }
      } catch {
        if (!cancelled) setCountryId(appUser.profile?.countryId ?? null);
      } finally {
        if (!cancelled) setBootstrapping(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [allowed, appUser.isReady, appUser.isSuperAdmin, appUser.profile?.countryId, appUser.profile?.id]);

  useEffect(() => {
    if (!countryId) {
      setCountryName(null);
      return;
    }
    const fromList = countries.find((country) => country.id === countryId)?.name;
    if (fromList) {
      setCountryName(fromList);
      return;
    }
    void supabase
      .from("Countries")
      .select("name")
      .eq("id", countryId)
      .maybeSingle()
      .then(({ data }) => setCountryName((data as { name?: string } | null)?.name ?? null));
  }, [countries, countryId]);

  if (!appUser.isReady || bootstrapping) {
    return (
      <div className="max-w-4xl mx-auto px-4 py-10 space-y-4">
        <Skeleton className="h-10 w-64" />
        <Skeleton className="h-40 w-full" />
      </div>
    );
  }

  if (!allowed) {
    return <Navigate to={`/${locale}/admin`} replace />;
  }

  return (
    <div className="max-w-4xl mx-auto px-4 py-8 pb-24 space-y-6">
      <div className="flex items-center gap-3 print:hidden">
        <Button variant="ghost" size="icon" asChild>
          <Link to={`/${locale}/admin`}>
            <ArrowLeftIcon className="h-4 w-4" />
          </Link>
        </Button>
        <div className="flex-1 min-w-0">
          <h1 className="text-xl font-bold tracking-tight">{t("commercial_offer.title")}</h1>
          <p className="text-sm text-muted-foreground mt-1">{t("commercial_offer.subtitle")}</p>
        </div>
      </div>

      <CommercialOfferDocumentPanel
        locale={locale}
        countryId={countryId}
        countryName={countryName}
        canSelectCountry={appUser.isSuperAdmin}
        countries={countries}
        onCountryChange={setCountryId}
      />
    </div>
  );
}
