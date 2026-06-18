import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { RocketIcon } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Switch } from "@/components/ui/switch.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import CompanyOwnerContractAcceptanceCheckbox from "@/components/legal/CompanyOwnerContractAcceptanceCheckbox.tsx";
import {
  acceptCompanyOwnerContractSupabase,
  getCompanyOwnerContractStatusSupabase,
  setCompanyArretReservationSupabase,
} from "@/lib/supabase/company-owner-contract.ts";

type Props = {
  companyId: string;
  countryId: string | null;
};

export default function CompanyGoLivePanel({ companyId, countryId }: Props) {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [acceptChecked, setAcceptChecked] = useState(false);
  const [status, setStatus] = useState<Awaited<
    ReturnType<typeof getCompanyOwnerContractStatusSupabase>
  > | null>(null);

  const load = () => {
    setLoading(true);
    void getCompanyOwnerContractStatusSupabase(companyId)
      .then(setStatus)
      .catch((err) => {
        toast.error(err instanceof Error ? err.message : t("company_go_live.load_error"));
        setStatus(null);
      })
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [companyId]);

  if (loading) {
    return (
      <Card>
        <CardContent className="pt-6">
          <Skeleton className="h-32 w-full" />
        </CardContent>
      </Card>
    );
  }

  if (!status) return null;

  const contractAccepted = Boolean(status.ownerContractAcceptedAt);
  const canGoLive = status.canEnableLive;

  const handleAcceptAndSave = async () => {
    if (!acceptChecked && !contractAccepted) {
      toast.error(t("company_owner_contract.required"));
      return;
    }
    setSaving(true);
    try {
      if (!contractAccepted) {
        await acceptCompanyOwnerContractSupabase(companyId);
      }
      toast.success(t("company_go_live.contract_saved"));
      setAcceptChecked(false);
      load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("company_go_live.save_error"));
    } finally {
      setSaving(false);
    }
  };

  const handleToggleLive = async (enabled: boolean) => {
    if (enabled && !canGoLive) {
      toast.error(t("company_go_live.contract_required"));
      return;
    }
    setSaving(true);
    try {
      await setCompanyArretReservationSupabase(companyId, enabled);
      toast.success(
        enabled ? t("company_go_live.enabled") : t("company_go_live.disabled"),
      );
      load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("company_go_live.save_error"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Card className="border-primary/20">
      <CardHeader className="pb-3">
        <CardTitle className="text-sm font-semibold flex items-center gap-2">
          <RocketIcon className="w-4 h-4 text-primary" />
          {t("company_go_live.title")}
        </CardTitle>
        <p className="text-xs text-muted-foreground">{t("company_go_live.desc")}</p>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap gap-2">
          <Badge variant={contractAccepted ? "default" : "secondary"}>
            {contractAccepted ? t("company_go_live.contract_ok") : t("company_go_live.contract_pending")}
          </Badge>
          {status.liveAuthorizedByAdmin ? (
            <Badge variant="outline">{t("company_go_live.admin_authorized")}</Badge>
          ) : null}
          <Badge variant={status.arretReservation ? "default" : "secondary"}>
            {status.arretReservation ? t("company_go_live.online") : t("company_go_live.offline")}
          </Badge>
        </div>

        {!contractAccepted && !status.liveAuthorizedByAdmin ? (
          <>
            <CompanyOwnerContractAcceptanceCheckbox
              checked={acceptChecked}
              onCheckedChange={setAcceptChecked}
              countryId={countryId}
            />
            <Button
              type="button"
              className="w-full"
              disabled={saving || !acceptChecked}
              onClick={() => void handleAcceptAndSave()}
            >
              {t("company_go_live.accept_btn")}
            </Button>
          </>
        ) : contractAccepted && status.ownerContractAcceptedAt ? (
          <p className="text-xs text-muted-foreground">
            {t("company_go_live.accepted_at", {
              date: new Date(status.ownerContractAcceptedAt).toLocaleString(),
            })}
          </p>
        ) : null}

        {status.liveAuthorizedByAdmin && !contractAccepted ? (
          <p className="text-xs text-amber-700 dark:text-amber-300 rounded-md border border-amber-500/30 bg-amber-500/10 p-3">
            {t("company_go_live.admin_bypass_hint")}
          </p>
        ) : null}

        <div className="flex items-center justify-between gap-3 rounded-lg border p-3">
          <div>
            <Label>{t("company_go_live.reservations_label")}</Label>
            <p className="text-xs text-muted-foreground mt-1">
              {t("company_go_live.reservations_hint")}
            </p>
          </div>
          <Switch
            checked={status.arretReservation}
            disabled={saving || ( !status.arretReservation && !canGoLive)}
            onCheckedChange={(checked) => void handleToggleLive(checked)}
          />
        </div>

        <Button asChild variant="outline" size="sm" className="w-full">
          <Link
            to={`/${lng ?? "fr"}/contrat-proprietaire-compagnie${countryId ? `?countryId=${countryId}` : ""}`}
            target="_blank"
            rel="noopener noreferrer"
          >
            {t("company_go_live.read_contract")}
          </Link>
        </Button>
      </CardContent>
    </Card>
  );
}
