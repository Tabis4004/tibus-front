import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { toast } from "sonner";
import { BuildingIcon, ImageIcon, SaveIcon } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import { Switch } from "@/components/ui/switch.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import {
  getOwnerCompanyDetailsSupabase,
  updateOwnerCompanySupabase,
  type OwnerCompanyDetails,
} from "@/lib/supabase/owner-company";

const companySchema = z.object({
  name: z.string().min(2, "Le nom doit contenir au moins 2 caractères"),
  logo: z.string().optional(),
  managerName: z.string().optional(),
  voyageColisMsg: z.string().max(500).optional(),
  arretReservation: z.boolean(),
});

type CompanyFormData = z.infer<typeof companySchema>;

export default function SupabaseCompanySettings() {
  const { t } = useTranslation("owner");
  const { appUserId } = useSupabaseAuth();
  const { companyId, isReady, isLoading: companyLoading } = useOwnerCompany();
  const [company, setCompany] = useState<OwnerCompanyDetails | null | undefined>(undefined);
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
      logo: "",
      managerName: "",
      voyageColisMsg: "",
      arretReservation: true,
    },
  });

  const arretReservation = watch("arretReservation");
  const logoUrl = watch("logo");

  useEffect(() => {
    if (!appUserId || !isReady) return;

    if (!companyId) {
      setCompany(null);
      return;
    }

    let cancelled = false;
    setCompany(undefined);
    void getOwnerCompanyDetailsSupabase(appUserId, companyId)
      .then((row) => {
        if (cancelled) return;
        setCompany(row);
        if (row) {
          reset({
            name: row.name,
            logo: row.logo ?? "",
            managerName: row.managerName ?? "",
            voyageColisMsg: row.voyageColisMsg ?? "",
            arretReservation: row.arretReservation,
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
  }, [appUserId, companyId, isReady, reset, t]);

  const onSubmit = async (data: CompanyFormData) => {
    if (!company || !companyId) return;
    setSaving(true);
    try {
      await updateOwnerCompanySupabase(company.id, {
        name: data.name.trim(),
        logo: data.logo?.trim() || null,
        managerName: data.managerName?.trim() || null,
        voyageColisMsg: data.voyageColisMsg?.trim() || null,
        arretReservation: data.arretReservation,
      });
      const refreshed = await getOwnerCompanyDetailsSupabase(appUserId!, companyId);
      setCompany(refreshed);
      if (refreshed) {
        reset({
          name: refreshed.name,
          logo: refreshed.logo ?? "",
          managerName: refreshed.managerName ?? "",
          voyageColisMsg: refreshed.voyageColisMsg ?? "",
          arretReservation: refreshed.arretReservation,
        });
      }
      toast.success(t("company.updated"));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("company.save_error"));
    } finally {
      setSaving(false);
    }
  };

  if (company === undefined || !isReady || companyLoading) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-6 space-y-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }

  if (!company) {
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
        <h1 className="text-2xl font-extrabold tracking-tight">{t("company.settings_title")}</h1>
        <p className="text-muted-foreground text-sm mt-1">{t("company.settings_desc")}</p>
      </div>

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
              {errors.logo && <p className="text-xs text-destructive">{errors.logo.message}</p>}
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
            <div className="flex items-center justify-between gap-3 rounded-lg border p-3">
              <div>
                <Label>Réservations en ligne</Label>
                <p className="text-xs text-muted-foreground">
                  Autoriser les réservations voyageur sur vos trajets.
                </p>
              </div>
              <Switch
                checked={arretReservation}
                onCheckedChange={(checked) =>
                  setValue("arretReservation", checked, { shouldDirty: true })
                }
              />
            </div>
          </CardContent>
        </Card>

        <Button type="submit" className="w-full" disabled={saving || !isDirty}>
          <SaveIcon className="w-4 h-4 mr-2" />
          {saving ? t("buttons.saving", { ns: "common" }) : t("company.save_btn")}
        </Button>
      </form>
    </div>
  );
}
