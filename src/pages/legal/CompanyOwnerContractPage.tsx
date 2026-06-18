import { useEffect, useState } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ArrowLeftIcon, FileTextIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table.tsx";
import {
  COMPANY_OWNER_CONTRACT_SLUG,
  getLegalPageSupabase,
  type LegalPage,
} from "@/lib/supabase/legal-pages.ts";
import {
  formatTechnicalAnnexText,
  type CommercialOfferTechnicalAnnex,
} from "@/lib/commercial-offer-annex.ts";
import { resolveTechnicalAnnexForCountry } from "@/lib/supabase/company-owner-contract.ts";

export default function CompanyOwnerContractPage() {
  const { lng } = useParams<{ lng: string }>();
  const [searchParams] = useSearchParams();
  const { t } = useTranslation("owner");
  const locale = lng ?? "fr";
  const home = `/${locale}`;
  const countryId = searchParams.get("countryId");

  const [page, setPage] = useState<LegalPage | null>(null);
  const [annex, setAnnex] = useState<CommercialOfferTechnicalAnnex | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);

    void (async () => {
      try {
        const [legal, annexResult] = await Promise.all([
          getLegalPageSupabase(COMPANY_OWNER_CONTRACT_SLUG),
          resolveTechnicalAnnexForCountry(countryId, locale),
        ]);
        if (cancelled) return;
        setPage(legal);
        setAnnex(annexResult.annex);
      } catch {
        if (!cancelled) {
          setPage(null);
          setAnnex(null);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [countryId, locale]);

  const annexText = annex ? formatTechnicalAnnexText(annex) : "";

  return (
    <div className="min-h-svh bg-background">
      <div className="max-w-3xl mx-auto px-4 py-8 space-y-6">
        <Button asChild variant="ghost" className="gap-2">
          <Link to={home}>
            <ArrowLeftIcon className="w-4 h-4" />
            {t("company_owner_contract.back", { defaultValue: "Retour" })}
          </Link>
        </Button>

        <Card>
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center">
                <FileTextIcon className="w-5 h-5 text-primary" />
              </div>
              <div>
                <CardTitle className="text-xl">
                  {loading ? (
                    <Skeleton className="h-7 w-64" />
                  ) : (
                    page?.title ??
                    t("company_owner_contract.title", {
                      defaultValue: "Contrat propriétaire de compagnie",
                    })
                  )}
                </CardTitle>
                {page?.updatedAt ? (
                  <p className="text-xs text-muted-foreground mt-1">
                    {t("company_owner_contract.updated_at", {
                      defaultValue: "Dernière mise à jour : {{date}}",
                      date: new Date(page.updatedAt).toLocaleString(),
                    })}
                  </p>
                ) : null}
              </div>
            </div>
          </CardHeader>
          <CardContent className="space-y-8">
            {loading ? (
              <div className="space-y-2">
                <Skeleton className="h-4 w-full" />
                <Skeleton className="h-4 w-full" />
                <Skeleton className="h-4 w-3/4" />
              </div>
            ) : (
              <>
                <article className="prose prose-sm dark:prose-invert max-w-none whitespace-pre-wrap text-sm leading-relaxed">
                  {page?.content ?? ""}
                </article>

                {annex ? (
                  <section className="space-y-4 border-t pt-6">
                    <div>
                      <h2 className="text-lg font-semibold">
                        {t("company_owner_contract.annex_title", {
                          defaultValue: "Annexe — Offre technique",
                        })}
                      </h2>
                      <p className="text-xs text-muted-foreground mt-1">
                        {t("company_owner_contract.annex_desc", {
                          defaultValue:
                            "Contenu aligné sur l'offre commerciale (section 2 — Architecture technique), personnalisable par pays dans Admin → Offre commerciale.",
                        })}
                      </p>
                    </div>

                    <h3 className="text-base font-semibold text-primary">{annex.heading}</h3>

                    <Table>
                      <TableHeader>
                        <TableRow>
                          {annex.architectureTable.headers.map((header) => (
                            <TableHead key={header}>{header}</TableHead>
                          ))}
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {annex.architectureTable.rows.map((row, index) => (
                          <TableRow key={`${row[0]}-${index}`}>
                            {row.map((cell, cellIndex) => (
                              <TableCell key={`${index}-${cellIndex}`} className="align-top text-sm">
                                {cell}
                              </TableCell>
                            ))}
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>

                    <div className="space-y-3">
                      <h4 className="text-sm font-semibold">
                        {t("company_owner_contract.modules_title", {
                          defaultValue: "Modules fonctionnels",
                        })}
                      </h4>
                      {annex.modules.map((module) => (
                        <div key={module.code} className="rounded-lg border p-3 text-sm">
                          <p className="font-medium">
                            Module {module.code} — {module.title}
                            {module.requires ? (
                              <span className="text-muted-foreground font-normal">
                                {" "}
                                ({t("company_owner_contract.requires_module", {
                                  defaultValue: "requiert module {{code}}",
                                  code: module.requires,
                                })})
                              </span>
                            ) : null}
                          </p>
                          <p className="text-muted-foreground mt-1">{module.description}</p>
                        </div>
                      ))}
                    </div>

                    <details className="text-xs text-muted-foreground">
                      <summary className="cursor-pointer">
                        {t("company_owner_contract.annex_plain", {
                          defaultValue: "Version texte intégrale de l'annexe",
                        })}
                      </summary>
                      <pre className="mt-2 whitespace-pre-wrap rounded-md bg-muted/40 p-3 text-xs">
                        {annexText}
                      </pre>
                    </details>
                  </section>
                ) : null}
              </>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
