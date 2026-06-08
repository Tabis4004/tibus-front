import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import {
  ArrowRightIcon,
  BuildingIcon,
  IdCardIcon,
  LogOutIcon,
  PencilIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { useAuth } from "@/hooks/use-auth.ts";
import { useAppUser, normalizeRoleForUi } from "@/hooks/use-app-user.ts";
import {
  canAccessGuaranteeFund,
  filterOwnerConsoleModules,
  groupOwnerConsoleModules,
  type OwnerConsoleModule,
} from "@/lib/owner-console-modules.tsx";
import type { OwnerCompany } from "@/lib/supabase/owner-company";
import GuaranteeFundOverviewCard from "./GuaranteeFundOverviewCard.tsx";

type Props = {
  company: OwnerCompany;
};

function ModuleBlock({
  module,
  lng,
  t,
}: {
  module: OwnerConsoleModule;
  lng: string;
  t: (key: string, options?: Record<string, string>) => string;
}) {
  const Icon = module.icon;

  return (
    <Link to={`/${lng}${module.toSuffix}`} className="block">
      <div className="rounded-xl border bg-card p-4 flex items-center gap-4 hover:border-primary/40 hover:shadow-sm transition-all group">
        <div className="w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
          <Icon className="w-5 h-5 text-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-sm leading-snug">
            {t(module.titleKey, { defaultValue: module.titleDefault })}
          </h3>
          <p className="text-xs text-muted-foreground mt-0.5 line-clamp-2">
            {t(module.descKey, { defaultValue: module.descDefault })}
          </p>
        </div>
        <ArrowRightIcon className="w-4 h-4 text-muted-foreground group-hover:text-primary shrink-0 transition-colors" />
      </div>
    </Link>
  );
}

export function OwnerProfileCard({ company }: { company: OwnerCompany }) {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const { user, signout } = useAuth();
  const appUser = useAppUser();

  const displayName = appUser.profile
    ? `${appUser.profile.firstName} ${appUser.profile.lastName}`.trim()
    : user?.name ?? t("console.default_user", { defaultValue: "Utilisateur Tibus" });

  return (
    <div className="rounded-xl border bg-card overflow-hidden">
      <div className="px-4 py-3 border-b bg-muted/20 flex items-center gap-2">
        <IdCardIcon className="w-4 h-4 text-primary" />
        <span className="font-semibold text-sm">{displayName}</span>
      </div>
      <div className="p-4 space-y-4">
        <div className="rounded-xl border bg-muted/30 p-3 space-y-2 text-sm">
          <div>
            <div className="text-[11px] uppercase tracking-wide text-muted-foreground">E-mail</div>
            <div className="font-medium break-all">{user?.email ?? appUser.profile?.email ?? "—"}</div>
          </div>
          {appUser.profile?.phone && (
            <div>
              <div className="text-[11px] uppercase tracking-wide text-muted-foreground">
                {t("company.phone", { defaultValue: "Téléphone" })}
              </div>
              <div className="font-medium">{appUser.profile.phone}</div>
            </div>
          )}
          <div>
            <div className="text-[11px] uppercase tracking-wide text-muted-foreground mb-1.5">
              {t("console.roles", { defaultValue: "Rôles reconnus" })}
            </div>
            <div className="flex flex-wrap gap-1.5">
              {appUser.roles.length > 0 ? (
                appUser.roles.map((role) => (
                  <Badge key={role} variant="secondary" className="text-[10px] capitalize">
                    {normalizeRoleForUi(role).replace(/_/g, " ")}
                  </Badge>
                ))
              ) : (
                <Badge variant="secondary" className="text-[10px]">
                  traveler
                </Badge>
              )}
            </div>
          </div>
          <div>
            <div className="text-[11px] uppercase tracking-wide text-muted-foreground">
              {t("console.company", { defaultValue: "Compagnie" })}
            </div>
            <div className="font-medium">{company.name}</div>
          </div>
        </div>

        <div className="flex flex-col gap-2">
          <Button asChild variant="secondary" size="sm" className="w-full border-2 border-primary/20">
            <Link to={`/${lng}/owner/company`}>
              <PencilIcon className="w-3.5 h-3.5 mr-1.5" />
              {t("buttons.edit", { ns: "common", defaultValue: "Modifier" })}
            </Link>
          </Button>
          <Button variant="outline" size="sm" className="w-full" onClick={() => void signout()}>
            <LogOutIcon className="w-3.5 h-3.5 mr-1.5" />
            {t("console.sign_out", { defaultValue: "Se déconnecter" })}
          </Button>
        </div>
      </div>
    </div>
  );
}

export function OwnerCompanyBanner({ company }: { company: OwnerCompany }) {
  return (
    <div className="rounded-xl border bg-card p-4 flex items-center gap-4">
      <div className="w-14 h-14 rounded-xl bg-primary/10 flex items-center justify-center shrink-0 overflow-hidden">
        {company.logo ? (
          <img src={company.logo} alt="" className="w-full h-full object-cover" />
        ) : (
          <BuildingIcon className="w-6 h-6 text-primary" />
        )}
      </div>
      <div className="flex-1 min-w-0">
        <h2 className="font-bold text-base truncate">{company.name}</h2>
        {company.managerName && (
          <p className="text-xs text-muted-foreground truncate">{company.managerName}</p>
        )}
        {company.currency && (
          <Badge variant="secondary" className="text-[10px] mt-1.5">
            {company.currency}
          </Badge>
        )}
      </div>
    </div>
  );
}

export default function OwnerConsoleModules({ company }: Props) {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const appUser = useAppUser();

  const modules = filterOwnerConsoleModules(appUser.roles, appUser.isSuperAdmin);
  const sections = groupOwnerConsoleModules(modules);
  const showGuaranteeFund = canAccessGuaranteeFund(appUser.roles, appUser.isSuperAdmin);

  return (
    <div className="space-y-6">
      {sections.map((section) => (
        <div key={section.sectionKey} className="space-y-2">
          <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider px-1">
            {t(section.sectionKey, { defaultValue: section.sectionDefault })}
          </h2>
          <div className="space-y-3">
            {section.items.map((module) =>
              module.id === "guarantee" && showGuaranteeFund ? (
                <GuaranteeFundOverviewCard key={module.id} companyId={company.id} />
              ) : (
                <ModuleBlock key={module.id} module={module} lng={lng ?? "fr"} t={t} />
              ),
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
