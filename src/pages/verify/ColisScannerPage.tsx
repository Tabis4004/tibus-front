import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { useCompanyFeatureModules } from "@/hooks/use-company-feature-modules.ts";
import { isSupabaseAuth } from "@/lib/auth/config";
import { resolveScannerCompanyId } from "@/lib/supabase/scanner-company.ts";
import ColisScanWorkflow, {
  ColisScanWorkflowHeader,
} from "@/pages/verify/_components/ColisScanWorkflow.tsx";

const SCANNER_ROLES = ["owner", "controleur", "vendeur", "chauffeur", "super_admin"] as const;

export default function ColisScannerPage() {
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const appUser = useAppUser();
  const [scannerCompanyId, setScannerCompanyId] = useState<string | null>(null);
  const { hasModule: hasFeatureModule, isLoading: featureModulesLoading } =
    useCompanyFeatureModules(scannerCompanyId);

  const hasAccess = SCANNER_ROLES.some((role) => appUser.roles.includes(role));
  const scannerUserId = appUser.profile?.id ?? null;

  useEffect(() => {
    if (!appUser.isReady || appUser.isLoading || !scannerUserId) return;
    void resolveScannerCompanyId(scannerUserId, appUser.roles)
      .then((companyId) => setScannerCompanyId(companyId))
      .catch(() => setScannerCompanyId(null));
  }, [scannerUserId, appUser.isReady, appUser.isLoading, appUser.roles]);

  useEffect(() => {
    if (!appUser.isReady || appUser.isLoading) return;
    if (!isSupabaseAuth()) {
      navigate(`/${lng ?? "fr"}`, { replace: true });
      return;
    }
    if (!hasAccess) {
      navigate(`/${lng ?? "fr"}`, { replace: true });
    }
  }, [appUser.isReady, appUser.isLoading, hasAccess, navigate, lng]);

  if (appUser.isLoading || featureModulesLoading) {
    return (
      <div className="max-w-lg mx-auto px-4 py-6 space-y-4">
        <Skeleton className="h-10 w-56 mx-auto" />
        <Skeleton className="h-[360px] w-full rounded-2xl" />
      </div>
    );
  }

  if (!hasAccess) return null;

  if (scannerCompanyId && !hasFeatureModule("D")) {
    return (
      <div className="max-w-lg mx-auto px-4 py-16 text-center space-y-3">
        <p className="font-medium">Scanner colis désactivé</p>
        <p className="text-sm text-muted-foreground">
          Le module D (expédition colis) n&apos;est pas activé pour cette compagnie.
        </p>
        <Button variant="outline" onClick={() => navigate(`/${lng ?? "fr"}/seller`)}>
          Retour guichet
        </Button>
      </div>
    );
  }

  return (
    <div className="max-w-lg mx-auto px-4 py-4 pb-28 space-y-5">
      <ColisScanWorkflowHeader />
      <ColisScanWorkflow />
    </div>
  );
}
