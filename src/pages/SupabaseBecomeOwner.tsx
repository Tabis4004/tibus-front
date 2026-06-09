import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { BuildingIcon, CheckCircleIcon, PlusIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/ui/card.tsx";
import { useAppUser } from "@/hooks/use-app-user";

export default function SupabaseBecomeOwner() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const { roles, isReady } = useAppUser();
  const isOwner = roles.includes("owner");
  const locale = lng ?? "fr";

  const perks = [
    t("become_owner.perk1"),
    t("become_owner.perk2"),
    t("become_owner.perk3"),
    t("become_owner.perk4"),
    t("become_owner.perk5"),
  ];

  const createHref = isOwner
    ? `/${locale}/owner/company?new=1`
    : `/${locale}/create-company`;

  return (
    <div className="max-w-md mx-auto px-4 py-10">
      <Card className="border-2 border-primary/20 shadow-lg">
        <CardHeader className="text-center pb-4">
          <div className="w-16 h-16 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
            <BuildingIcon className="w-8 h-8 text-primary" />
          </div>
          <CardTitle className="text-2xl">
            {isOwner ? t("become_owner.another_title", { defaultValue: "Créer une autre compagnie" }) : t("become_owner.title")}
          </CardTitle>
          <CardDescription>
            {isOwner
              ? t("become_owner.another_desc", {
                  defaultValue:
                    "Ajoutez une nouvelle entreprise de transport dans un autre pays ou sous un autre nom.",
                })
              : t("become_owner.desc")}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          <ul className="space-y-3">
            {perks.map((perk) => (
              <li key={perk} className="flex items-center gap-3 text-sm">
                <CheckCircleIcon className="w-5 h-5 text-primary shrink-0" />
                <span>{perk}</span>
              </li>
            ))}
          </ul>
          <Button asChild className="w-full" size="lg" disabled={!isReady}>
            <Link to={createHref}>
              <PlusIcon className="w-4 h-4 mr-2" />
              {isOwner
                ? t("become_owner.another_btn", { defaultValue: "Créer une compagnie" })
                : t("become_owner.btn")}
            </Link>
          </Button>
          {isOwner ? (
            <Button asChild variant="secondary" className="w-full">
              <Link to={`/${locale}/owner`}>
                {t("become_owner.back_owner", { defaultValue: "Retour au tableau de bord" })}
              </Link>
            </Button>
          ) : null}
          <p className="text-xs text-center text-muted-foreground">{t("become_owner.note")}</p>
        </CardContent>
      </Card>
    </div>
  );
}
