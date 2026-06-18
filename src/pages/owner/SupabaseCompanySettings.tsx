import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { toast } from "sonner";
import { useNavigate, useParams, useSearchParams, useLocation } from "react-router-dom";
import { BuildingIcon, ImageIcon, SaveIcon } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { refreshAppUser } from "@/hooks/use-app-user.ts";
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import {
  createOwnerCompanySupabase,
  getOwnerCompanyDetailsSupabase,
  updateOwnerCompanySupabase,
  type OwnerCompanyDetails,
} from "@/lib/supabase/owner-company";
import { listCountriesSupabase, type CountryRow } from "@/lib/supabase/geography";
import CompanyGoLivePanel from "./_components/CompanyGoLivePanel.tsx";

const companySchema = z.object({
  name: z.string().min(2, "Le nom doit contenir au moins 2 caractères"),
  countryId: z.string().optional(),
  logo: z.string().optional(),
  managerName: z.string().optional(),
  voyageColisMsg: z.string().max(500).optional(),
});

type CompanyFormData = z.infer<typeof companySchema>;

export default function SupabaseCompanySettings() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const location = useLocation();
  const { appUserId } = useSupabaseAuth();
  const { companyId, isReady, isLoading: companyLoading, refresh, setSelectedCompanyId } =
    useOwnerCompany();
  const isStandaloneCreate = /\/create-company\/?$/.test(location.pathname);
  const isCreateMode =
    isStandaloneCreate || searchParams.get("new") === "1" || !companyId;
  const [company, setCompany] = useState<OwnerCompanyDetails | null | undefined>(undefined);
  const [countries, setCountries] = useState<CountryRow[]>([]);
  const [saving, setSaving] = useState(false);

  const {
    register,
    handleSubmit,
    reset,
    watch,
    setValue,
    formState: { errors, isDirty },
  } = useForm<CompanyFormData>({
    resolver: zodResolver(companySchema),
    defaultValues: {
      name: "",
      countryId: "",
      logo: "",
      managerName: "",
      voyageColisMsg: "",
    },
  });

  const logoUrl = watch("logo");
  const countryIdValue = watch("countryId");

  useEffect(() => {
    void listCountriesSupabase()
      .then(setCountries)
      .catch(() => setCountries([]));
  }, []);

  useEffect(() => {
    if (!isCreateMode || !countries.length) return;
    if (!countryIdValue) {
      setValue("countryId", countries[0]._id, { shouldDirty: false });
    }
  }, [isCreateMode, countries, countryIdValue, setValue]);

  useEffect(() => {
    if (!appUserId || !isReady) return;

    if (isCreateMode) {
      setCompany(null);
      reset({
        name: "",
        countryId: countries[0]?._id ?? "",
        logo: "",
        managerName: "",
        voyageColisMsg: "",
      });
      return;
    }

    if (!companyId) return;

    let cancelled = false;
    setCompany(undefined);
    void getOwnerCompanyDetailsSupabase(appUserId, companyId)
      .then((row) => {
        if (cancelled) return;
        setCompany(row);
        if (row) {
          reset({
            name: row.name,
            countryId: row.countryId ?? "",
            logo: row.logo ?? "",
            managerName: row.managerName ?? "",
            voyageColisMsg: row.voyageColisMsg ?? "",
          });
        }
      })
      .catch((err) => {
        if (!cancelled) {
          setCompany(null);
          toast.error(err instanceof Error ? err.message : t("company.save_error"));
        }
      });
    return () => {
      cancelled = true;
    };
  }, [appUserId, companyId, isReady, isCreateMode, reset, t, countries]);

  const onSubmit = async (data: CompanyFormData) => {
    setSaving(true);
    try {
      if (isCreateMode) {
        if (!data.countryId) {
          toast.error(t("company.country_required", { defaultValue: "Sélectionnez un pays" }));
          return;
        }
        const newCompanyId = await createOwnerCompanySupabase({
          name: data.name,
          countryId: data.countryId,
          managerName: data.managerName,
          logo: data.logo,
          voyageColisMsg: data.voyageColisMsg,
          arretReservation: false,
        });
        refreshAppUser();
        refresh();
        await setSelectedCompanyId(newCompanyId);
        toast.success(t("company.created"));
        toast.message(t("company_go_live.after_create_hint"));
        navigate(`/${lng ?? "fr"}/owner/company`, { replace: true });
        return;
      }

      if (!company || !companyId) return;
      await updateOwnerCompanySupabase(company.id, {
        name: data.name.trim(),
        logo: data.logo?.trim() || null,
        managerName: data.managerName?.trim() || null,
        voyageColisMsg: data.voyageColisMsg?.trim() || null,
      });
      const refreshed = await getOwnerCompanyDetailsSupabase(appUserId!, companyId);
      setCompany(refreshed);
      if (refreshed) {
        reset({
          name: refreshed.name,
          countryId: refreshed.countryId ?? countryIdValue,
          logo: refreshed.logo ?? "",
          managerName: refreshed.managerName ?? "",
          voyageColisMsg: refreshed.voyageColisMsg ?? "",
        });
      }
      toast.success(t("company.updated"));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("company.save_error"));
    } finally {
      setSaving(false);
    }
  };

  if (!isCreateMode && (company === undefined || !isReady || companyLoading)) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }

  if (!isCreateMode && !company) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-6">
        <h1 className="text-2xl font-extrabold">{t("overview.no_company")}</h1>
        <p className="text-sm text-muted-foreground mt-2">{t("overview.no_company_desc")}</p>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-6">
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">
          {isCreateMode ? t("company.create_title") : t("company.settings_title")}
        </h1>
        <p className="text-muted-foreground text-sm mt-1">
          {isCreateMode ? t("company.create_desc") : t("company.settings_desc")}
        </p>
      </div>

      {!isCreateMode && companyId ? (
        <CompanyGoLivePanel companyId={companyId} countryId={company?.countryId ?? null} />
      ) : null}

      <form onSubmit={handleSubmit(onSubmit)} className="space-y-5">
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold flex items-center gap-2">
              <ImageIcon className="w-4 h-4" /> {t("company.logo")}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {logoUrl ? (
              <img
                src={logoUrl}
                alt="Logo"
                className="w-20 h-20 rounded-xl object-cover border"
                onError={(e) => {
                  (e.target as HTMLImageElement).style.display = "none";
                }}
              />
            ) : null}
            <div className="space-y-1.5">
              <Label htmlFor="logo">{t("company.logo_url")}</Label>
              <Input id="logo" placeholder="https://..." {...register("logo")} />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-sm font-semibold flex items-center gap-2">
              <BuildingIcon className="w-4 h-4" /> {t("company.basic_info")}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {isCreateMode ? (
              <div className="space-y-1.5">
                <Label>
                  {t("stations.country", { defaultValue: "Pays" })}{" "}
                  <span className="text-destructive">*</span>
                </Label>
                <Select
                  value={countryIdValue || undefined}
                  onValueChange={(value) =>
                    setValue("countryId", value, { shouldDirty: true })
                  }
                >
                  <SelectTrigger>
                    <SelectValue placeholder={t("stations.country", { defaultValue: "Pays" })} />
                  </SelectTrigger>
                  <SelectContent>
                    {countries.map((country) => (
                      <SelectItem key={country._id} value={country._id}>
                        {country.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                {errors.countryId && (
                  <p className="text-xs text-destructive">{errors.countryId.message}</p>
                )}
              </div>
            ) : null}
            <div className="space-y-1.5">
              <Label htmlFor="name">
                {t("company.name")} <span className="text-destructive">*</span>
              </Label>
              <Input id="name" {...register("name")} />
              {errors.name && <p className="text-xs text-destructive">{errors.name.message}</p>}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="managerName">Responsable</Label>
              <Input id="managerName" {...register("managerName")} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="voyageColisMsg">Message embarquement / colis</Label>
              <Textarea id="voyageColisMsg" rows={3} {...register("voyageColisMsg")} />
            </div>
          </CardContent>
        </Card>

        <Button type="submit" className="w-full" disabled={saving || (!isCreateMode && !isDirty)}>
          <SaveIcon className="w-4 h-4 mr-2" />
          {saving
            ? t("buttons.saving", { ns: "common" })
            : isCreateMode
              ? t("company.create_btn")
              : t("company.save_btn")}
        </Button>
      </form>
    </div>
  );
}
