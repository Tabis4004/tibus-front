import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ExternalLinkIcon, ShieldCheckIcon } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Switch } from "@/components/ui/switch.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { isAdminPaysRole } from "@/lib/auth/company-access.ts";
import { COMPANY_OWNER_CONTRACT_PATH } from "@/lib/supabase/legal-pages.ts";
import {
  getCompanyOwnerContractStatusSupabase,
  setCompanyActiveAdminSupabase,
  setCompanyLiveAuthorizationSupabase,
  type CompanyOwnerContractStatus,
} from "@/lib/supabase/company-owner-contract.ts";

type Props = {
  companyId: string;
  countryId: string | null;
};

export default function CompanyLiveAuthorizationPanel({ companyId, countryId }: Props) {
  const { t } = useTranslation("admin");
  const { lng } = useParams<{ lng: string }>();
  const { isSuperAdmin, roles } = useAppUser();
  const canManage = isSuperAdmin || isAdminPaysRole(roles);
  const [status, setStatus] = useState<CompanyOwnerContractStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const load = () => {
    setLoading(true);
    void getCompanyOwnerContractStatusSupabase(companyId)
      .then(setStatus)
      .catch((err) => {
        toast.error(err instanceof Error ? err.message : t("company_live.load_error"));
        setStatus(null);
      })
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    if (!canManage) return;
    load();
  }, [companyId, canManage]);

  if (!canManage) return null;

  if (loading) {
    return (
      <Card>
        <CardContent className="pt-6">
          <Skeleton className="h-24 w-full" />
        </CardContent>
      </Card>
    );
  }

  if (!status) return null;

  const contractAccepted = Boolean(status.ownerContractAcceptedAt);

  const handleAuthorize = async (authorized: boolean) => {
    setSaving(true);
    try {
      await setCompanyLiveAuthorizationSupabase(companyId, authorized);
      toast.success(
        authorized
          ? t("company_live.authorized_on")
          : t("company_live.authorized_off"),
      );
      load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("company_live.save_error"));
    } finally {
      setSaving(false);
    }
  };

  const handleActive = async (isActive: boolean) => {
    setSaving(true);
    try {
      await setCompanyActiveAdminSupabase(companyId, isActive);
      toast.success(isActive ? t("company_live.activated") : t("company_live.deactivated"));
      load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("company_live.save_error"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <ShieldCheckIcon className="w-4 h-4" />
          {t("company_live.title")}
        </CardTitle>
        <p className="text-xs text-muted-foreground">{t("company_live.desc")}</p>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap gap-2">
          <Badge variant={contractAccepted ? "default" : "secondary"}>
            {contractAccepted ? t("company_live.contract_ok") : t("company_live.contract_pending")}
          </Badge>
          {status.liveAuthorizedByAdmin ? (
            <Badge variant="outline">{t("company_live.test_auth_badge")}</Badge>
          ) : null}
          <Badge variant={status.isActive ? "default" : "secondary"}>
            {status.isActive ? t("company_live.live") : t("company_live.not_live")}
          </Badge>
        </div>

        {status.ownerContractAcceptedAt ? (
          <p className="text-xs text-muted-foreground">
            {t("company_live.accepted_at", {
              date: new Date(status.ownerContractAcceptedAt).toLocaleString(),
            })}
          </p>
        ) : null}

        <div className="flex items-center justify-between gap-3 rounded-lg border p-3">
          <div>
            <Label>{t("company_live.authorize_test")}</Label>
            <p className="text-xs text-muted-foreground mt-1">{t("company_live.authorize_test_hint")}</p>
          </div>
          <Switch
            checked={status.liveAuthorizedByAdmin}
            disabled={saving}
            onCheckedChange={(checked) => void handleAuthorize(checked)}
          />
        </div>

        <div className="flex items-center justify-between gap-3 rounded-lg border p-3">
          <div>
            <Label>{t("company_live.activate_company")}</Label>
            <p className="text-xs text-muted-foreground mt-1">{t("company_live.activate_company_hint")}</p>
          </div>
          <Switch
            checked={status.isActive}
            disabled={saving}
            onCheckedChange={(checked) => void handleActive(checked)}
          />
        </div>

        <Button asChild variant="outline" size="sm" className="gap-2">
          <Link
            to={`/${lng ?? "fr"}/${COMPANY_OWNER_CONTRACT_PATH}${countryId ? `?countryId=${countryId}` : ""}`}
            target="_blank"
            rel="noopener noreferrer"
          >
            <ExternalLinkIcon className="w-4 h-4" />
            {t("company_live.view_contract")}
          </Link>
        </Button>
      </CardContent>
    </Card>
  );
}
