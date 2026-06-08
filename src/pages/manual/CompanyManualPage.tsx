import { useEffect } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ArrowLeftIcon, BookOpenIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import {
  canAccessCompanyManual,
  COMPANY_MANUAL_SECTIONS,
  COMPANY_MANUAL_SUBTITLE,
  COMPANY_MANUAL_TITLE,
  type ManualFigure,
  type ManualSection,
  type ManualSubsection,
} from "@/data/company-manual-content.ts";

function ManualFigureBlock({ figure }: { figure: ManualFigure }) {
  return (
    <figure className="my-5 space-y-2">
      <img
        src={figure.src}
        alt={figure.caption}
        className="w-full rounded-xl border bg-card shadow-sm"
        loading="lazy"
      />
      <figcaption className="text-center text-xs text-muted-foreground italic px-2">
        {figure.caption}
      </figcaption>
    </figure>
  );
}

function ManualSubsectionBlock({ item }: { item: ManualSubsection }) {
  return (
    <div className="rounded-xl border bg-card p-4 space-y-3">
      <h4 className="font-semibold text-sm text-[#1A5296]">{item.title}</h4>
      <p className="text-sm text-muted-foreground leading-relaxed">{item.body}</p>
      {item.bullets?.length ? (
        <ul className="list-disc pl-5 space-y-1 text-sm text-muted-foreground">
          {item.bullets.map((bullet) => (
            <li key={bullet}>{bullet}</li>
          ))}
        </ul>
      ) : null}
      {item.figure ? <ManualFigureBlock figure={item.figure} /> : null}
    </div>
  );
}

function ManualSectionBlock({ section }: { section: ManualSection }) {
  return (
    <section id={section.id} className="scroll-mt-24 space-y-4">
      <h2 className="text-xl font-extrabold tracking-tight text-[#1A5296]">{section.title}</h2>
      {section.intro ? <p className="text-sm text-muted-foreground">{section.intro}</p> : null}
      {section.paragraphs?.map((paragraph) => (
        <p key={paragraph} className="text-sm leading-relaxed">
          {paragraph}
        </p>
      ))}
      {section.bullets?.length ? (
        <ul className="list-disc pl-5 space-y-1.5 text-sm leading-relaxed">
          {section.bullets.map((bullet) => (
            <li key={bullet}>{bullet}</li>
          ))}
        </ul>
      ) : null}
      {section.numbered?.length ? (
        <ol className="list-decimal pl-5 space-y-1.5 text-sm leading-relaxed">
          {section.numbered.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ol>
      ) : null}
      {section.figure ? <ManualFigureBlock figure={section.figure} /> : null}
      {section.subsections?.length ? (
        <div className={section.id === "owner" ? "grid gap-4 md:grid-cols-2" : "space-y-3"}>
          {section.subsections.map((item) => (
            <ManualSubsectionBlock key={item.title} item={item} />
          ))}
        </div>
      ) : null}
    </section>
  );
}

export default function CompanyManualPage() {
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const { t } = useTranslation("common");
  const appUser = useAppUser();
  const locale = lng ?? "fr";
  const home = `/${locale}`;
  const canAccess = canAccessCompanyManual(appUser.roles, appUser.isSuperAdmin);

  useEffect(() => {
    if (appUser.isReady && !canAccess) {
      navigate(home, { replace: true });
    }
  }, [appUser.isReady, canAccess, home, navigate]);

  if (!appUser.isReady || appUser.isLoading) {
    return (
      <div className="max-w-4xl mx-auto px-4 py-8 space-y-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }

  if (!canAccess) {
    return null;
  }

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
                {t("manual.restricted_badge", { defaultValue: "Owner & Super admin" })}
              </Badge>
            </div>
            <h1 className="text-2xl font-extrabold tracking-tight text-[#1A5296]">
              {t("manual.title", { defaultValue: COMPANY_MANUAL_TITLE })}
            </h1>
            <p className="text-sm text-muted-foreground mt-1">
              {t("manual.subtitle", { defaultValue: COMPANY_MANUAL_SUBTITLE })}
            </p>
          </div>
          <div className="hidden sm:flex w-11 h-11 rounded-xl bg-primary/10 items-center justify-center shrink-0">
            <BookOpenIcon className="w-5 h-5 text-primary" />
          </div>
        </div>

        <p className="text-sm leading-relaxed text-muted-foreground">
          {t("manual.intro", {
            defaultValue:
              "Ce document décrit les menus et les actions de chaque profil utilisateur sur Tibus. Il s'adresse aux gérants et super administrateurs pour former leurs équipes.",
          })}
        </p>

        <nav className="rounded-xl border bg-muted/30 p-4">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3">
            {t("manual.toc", { defaultValue: "Sommaire" })}
          </p>
          <div className="grid gap-2 sm:grid-cols-2">
            {COMPANY_MANUAL_SECTIONS.map((section) => (
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
          {COMPANY_MANUAL_SECTIONS.map((section) => (
            <ManualSectionBlock key={section.id} section={section} />
          ))}
        </div>

        <p className="text-center text-xs text-muted-foreground italic pt-4 border-t">
          {t("manual.footer", {
            defaultValue: "Document Tibus · Compagnie de transport · Compte démo : tabiscompany@gmail.com",
          })}
        </p>
      </div>
    </div>
  );
}
