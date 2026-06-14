import { useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { BookOpenIcon } from "lucide-react";
import { getManualNavItems } from "@/lib/manual-nav.ts";
import { useAuth } from "@/hooks/use-auth.ts";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { HomeActionBlock } from "./HomeActionBlock.tsx";

export function HomeManualBlocks() {
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("common");
  const { isAuthenticated } = useAuth();
  const appUser = useAppUser();
  const locale = lng ?? "fr";

  const items = getManualNavItems({
    roles: appUser.isReady ? appUser.roles : [],
    isSuperAdmin: appUser.isReady ? appUser.isSuperAdmin : false,
    isAuthenticated,
  });

  return (
    <>
      {items.map((item) => (
        <HomeActionBlock
          key={item.toSuffix}
          to={`/${locale}${item.toSuffix}`}
          title={t(item.labelKey, { defaultValue: item.labelDefault })}
          description={t(
            item.toSuffix.includes("admin-pays")
              ? "manual.country_admin_nav_desc"
              : "manual.nav_desc",
            {
              defaultValue: item.toSuffix.includes("admin-pays")
                ? "Guide admin pays — commissions et fond de garantie"
                : "Guide complet pour former vos équipes",
            },
          )}
          icon={BookOpenIcon}
        />
      ))}
    </>
  );
}
