import type { ReactNode } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ShieldIcon } from "lucide-react";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { hasPlatformScope } from "@/lib/auth/platform-scope.ts";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";

export default function AdminAccessGate({
  children,
  requireSuperAdmin = false,
}: {
  children: ReactNode;
  requireSuperAdmin?: boolean;
}) {
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const appUser = useAppUser();

  const canAccess = requireSuperAdmin
    ? appUser.isSuperAdmin
    : hasPlatformScope(appUser.roles, appUser.isSuperAdmin);

  if (!appUser.isReady || appUser.isLoading) {
    return (
      <div className="max-w-6xl mx-auto px-4 py-8 space-y-4">
        <Skeleton className="h-10 w-64" />
        <Skeleton className="h-40 w-full" />
      </div>
    );
  }

  if (!canAccess) {
    return (
      <div className="max-w-lg mx-auto px-4 py-16">
        <Card>
          <CardContent className="pt-6 space-y-4 text-center">
            <div className="mx-auto w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center">
              <ShieldIcon className="w-6 h-6 text-primary" />
            </div>
            <div className="space-y-1">
              <h1 className="text-lg font-bold">
                {t("access_denied.title", { defaultValue: "Accès admin requis" })}
              </h1>
              <p className="text-sm text-muted-foreground">
                {t("access_denied.desc", {
                  defaultValue:
                    "Connectez-vous avec un compte plateforme (super admin ou admin pays) pour accéder à cette page.",
                })}
              </p>
            </div>
            <Button asChild className="cursor-pointer">
              <Link to={`/${lng ?? "fr"}/auth/login`}>
                {tc("auth.sign_in", { defaultValue: "Se connecter" })}
              </Link>
            </Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  return <>{children}</>;
}
