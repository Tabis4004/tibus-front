import { useEffect, type ReactNode } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import type { CompanyFeatureModuleId } from "@/lib/company-feature-modules.ts";
import { useCompanyFeatureModules } from "@/hooks/use-company-feature-modules.ts";
import { useOwnerCompanyOptional } from "@/hooks/use-owner-company.tsx";

type Props = {
  module: CompanyFeatureModuleId;
  companyId?: string | null;
  children: ReactNode;
};

/** Redirige vers la console owner si le module commercial n'est pas actif pour la compagnie. */
export default function CompanyFeatureModuleGuard({ module, companyId, children }: Props) {
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const { t } = useTranslation("owner");
  const ownerCtx = useOwnerCompanyOptional();
  const resolvedCompanyId = companyId ?? ownerCtx?.companyId ?? null;
  const { modules, isLoading, hasModule } = useCompanyFeatureModules(resolvedCompanyId);

  useEffect(() => {
    if (isLoading || !modules) return;
    if (!hasModule(module)) {
      toast.error(
        t("feature_modules.disabled", {
          defaultValue: "Ce module n'est pas activé pour votre compagnie.",
        }),
      );
      navigate(`/${lng ?? "fr"}/owner`, { replace: true });
    }
  }, [isLoading, modules, hasModule, module, navigate, lng, t]);

  if (!resolvedCompanyId || isLoading) {
    return (
      <div className="p-6 space-y-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-40 w-full rounded-xl" />
      </div>
    );
  }

  if (modules && !hasModule(module)) return null;

  return <>{children}</>;
}
