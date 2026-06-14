import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ArrowLeftIcon, BookOpenIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import {
  COUNTRY_ADMIN_MANUAL_SECTIONS,
  COUNTRY_ADMIN_MANUAL_SUBTITLE,
  COUNTRY_ADMIN_MANUAL_TITLE,
} from "@/data/country-admin-manual-content.ts";
import { ManualSectionBlock } from "./_components/manual-blocks.tsx";

export default function CountryAdminManualPage() {
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("common");
  const locale = lng ?? "fr";
  const home = `/${locale}`;

  return (
    <div className="min-h-svh bg-background">
      <div className="max-w-4xl mx-auto px-4 py-6 pb-24 space-y-8">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" asChild>
            <Link to={home}>
              <ArrowLeftIcon className="h-4 w-4" />
            </Link>
          </Button>
          <div className="flex-1 min-w-0">
            <div className="flex flex-wrap items-center gap-2 mb-1">
              <Badge variant="secondary" className="text-[10px] uppercase tracking-wide">
                {t("manual.public_badge", { defaultValue: "Documentation publique" })}
              </Badge>
            </div>
            <h1 className="text-2xl font-extrabold tracking-tight text-[#1A5296]">
              {t("manual.country_admin_title", { defaultValue: COUNTRY_ADMIN_MANUAL_TITLE })}
            </h1>
            <p className="text-sm text-muted-foreground mt-1">
              {t("manual.country_admin_subtitle", { defaultValue: COUNTRY_ADMIN_MANUAL_SUBTITLE })}
            </p>
          </div>
          <div className="hidden sm:flex w-11 h-11 rounded-xl bg-primary/10 items-center justify-center shrink-0">
            <BookOpenIcon className="w-5 h-5 text-primary" />
          </div>
        </div>

        <p className="text-sm leading-relaxed text-muted-foreground">
          {t("manual.country_admin_intro", {
            defaultValue:
              "Ce document explique à quoi sert le rôle admin pays sur Tibus, quels écrans vous pouvez utiliser et comment paramétrer commissions et fond de garantie pour votre territoire.",
          })}
        </p>

        <nav className="rounded-xl border bg-muted/30 p-4">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
            {t("manual.toc", { defaultValue: "Sommaire" })}
          </p>
          <div className="grid gap-2 sm:grid-cols-2">
            {COUNTRY_ADMIN_MANUAL_SECTIONS.map((section) => (
              <a
                key={section.id}
                href={`#${section.id}`}
                className="text-sm text-primary hover:underline"
              >
                {section.title}
              </a>
            ))}
          </div>
        </nav>

        <div className="space-y-10">
          {COUNTRY_ADMIN_MANUAL_SECTIONS.map((section) => (
            <ManualSectionBlock key={section.id} section={section} />
          ))}
        </div>

        <p className="text-center text-xs text-muted-foreground italic pt-4 border-t">
          {t("manual.country_admin_footer", {
            defaultValue: "Document Tibus · Administration pays",
          })}
        </p>
      </div>
    </div>
  );
}
