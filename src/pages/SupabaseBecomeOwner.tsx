import { Link, useNavigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { useEffect } from "react";
import { BuildingIcon, CheckCircleIcon, MailIcon } from "lucide-react";
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
  const navigate = useNavigate();
  const { roles, isReady } = useAppUser();
  const isOwner = roles.includes("owner");

  useEffect(() => {
    if (isReady && isOwner) {
      navigate(`/${lng ?? "fr"}/owner`, { replace: true });
    }
  }, [isReady, isOwner, lng, navigate]);

  const perks = [
    t("become_owner.perk1"),
    t("become_owner.perk2"),
    t("become_owner.perk3"),
    t("become_owner.perk4"),
    t("become_owner.perk5"),
  ];

  return (
    <div className="max-w-md mx-auto px-4 py-10">
      <Card className="border-2 border-primary/20 shadow-lg">
        <CardHeader className="text-center pb-4">
          <div className="w-16 h-16 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
            <BuildingIcon className="w-8 h-8 text-primary" />
          </div>
          <CardTitle className="text-2xl">{t("become_owner.title")}</CardTitle>
          <CardDescription>{t("become_owner.desc")}</CardDescription>
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
          <Button asChild className="w-full" size="lg">
            <Link to={`/${lng ?? "fr"}/contact`}>
              <MailIcon className="w-4 h-4 mr-2" />
              {t("become_owner.btn")}
            </Link>
          </Button>
          <p className="text-xs text-center text-muted-foreground">
            {t("become_owner.note")} — un administrateur Tibus créera votre compagnie et
            vous assignera le rôle transporteur.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
