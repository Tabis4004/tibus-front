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
import { useOwnerCompany } from "@/hooks/use-owner-company.tsx";
import type { OwnerCompany } from "@/lib/supabase/owner-company";
import GuaranteeFundOverviewCard from "./GuaranteeFundOverviewCard.tsx";
import ConsoleBlocksShell from "@/components/console/ConsoleBlocksShell.tsx";
import { useConsoleBlocksCustomize } from "@/components/console/ConsoleBlocksCustomizeContext.tsx";
import ConsoleTilePalettePicker from "@/components/console/ConsoleTilePalettePicker.tsx";
import { cn } from "@/lib/utils.ts";
import { resolveConsoleTileStyle } from "@/lib/console-grid-tiles.ts";

type Props = {
  company: OwnerCompany;
};

function ModuleBlock({
  module,
  lng,
  t,
  tileIndex,
}: {
  module: OwnerConsoleModule;
  lng: string;
  t: (key: string, options?: Record<string, string>) => string;
  tileIndex: number;
}) {
  const Icon = module.icon;
  const customize = useConsoleBlocksCustomize();
  const blockId = `owner-${module.id}`;
  const style = customize
    ? customize.styleFor(blockId, tileIndex)
    : resolveConsoleTileStyle(tileIndex);
  const showPicker = Boolean(customize?.customizeMode);

  const inner = (
    <div
      className={cn(
        "h-full min-h-[132px] rounded-2xl border p-4 flex flex-col items-center justify-center text-center gap-2.5",
        !showPicker && "hover:shadow-md transition-all group",
        style.tile,
        style.border,
      )}
    >
      <div className={cn("w-12 h-12 rounded-2xl flex items-center justify-center shadow-sm", style.iconWrap)}>
        <Icon className={cn("w-6 h-6", style.icon)} />
      </div>
      <div className="min-w-0 w-full">
        <h3 className={cn("font-semibold text-sm leading-snug", style.title)}>
          {t(module.titleKey, { defaultValue: module.titleDefault })}
        </h3>
        <p className="text-[11px] text-muted-foreground mt-1 line-clamp-2 leading-snug">
          {t(module.descKey, { defaultValue: module.descDefault })}
        </p>
      </div>
      {!showPicker ? (
        <div className="flex items-center gap-1 text-[10px] font-medium text-muted-foreground group-hover:text-foreground">
          Ouvrir
          <ArrowRightIcon className="w-3 h-3 shrink-0 transition-transform group-hover:translate-x-0.5" />
        </div>
      ) : null}
      {showPicker && customize ? (
        <ConsoleTilePalettePicker
          blockId={blockId}
          selectedIndex={customize.paletteIndexFor(blockId, tileIndex)}
          defaultIndex={tileIndex}
          onSelect={(index) => customize.setBlockColor(blockId, index)}
          onReset={() => customize.resetBlockColor(blockId)}
        />
      ) : null}
    </div>
  );

  if (showPicker) {
    return (
      <div className="block h-full" data-tour={module.tourTarget}>
        {inner}
      </div>
    );
  }

  return (
    <Link to={`/${lng}${module.toSuffix}`} className="block h-full" data-tour={module.tourTarget}>
      {inner}
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
  const { featureModules } = useOwnerCompany();

  const modules = filterOwnerConsoleModules(
    appUser.roles,
    appUser.isSuperAdmin,
    featureModules,
  );
  const sections = groupOwnerConsoleModules(modules);
  const showGuaranteeFund = canAccessGuaranteeFund(appUser.roles, appUser.isSuperAdmin);

  return (
    <ConsoleBlocksShell userId={appUser.profile?.id ?? null} surface="owner" className="mb-2">
      <div className="space-y-6">
        {sections.map((section) => (
          <div key={section.sectionKey} className="space-y-2">
            <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider px-1">
              {t(section.sectionKey, { defaultValue: section.sectionDefault })}
            </h2>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              {section.items.map((module, index) =>
                module.id === "guarantee" && showGuaranteeFund ? (
                  <GuaranteeFundOverviewCard key={module.id} companyId={company.id} />
                ) : (
                  <ModuleBlock key={module.id} module={module} lng={lng ?? "fr"} t={t} tileIndex={index} />
                ),
              )}
            </div>
          </div>
        ))}
      </div>
    </ConsoleBlocksShell>
  );
}
