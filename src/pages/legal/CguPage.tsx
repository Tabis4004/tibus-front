import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ArrowLeftIcon, FileTextIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { getCguPageSupabase, type LegalPage } from "@/lib/supabase/legal-pages.ts";

export default function CguPage() {
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("common");
  const [page, setPage] = useState<LegalPage | null>(null);
  const [loading, setLoading] = useState(true);
  const home = `/${lng ?? "fr"}`;

  useEffect(() => {
    void getCguPageSupabase()
      .then(setPage)
      .catch(() => setPage(null))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="min-h-svh bg-background">
      <div className="max-w-3xl mx-auto px-4 py-8 space-y-6">
        <Button asChild variant="ghost" className="gap-2">
          <Link to={home}>
            <ArrowLeftIcon className="w-4 h-4" />
            {t("actions.back_home", { defaultValue: "Retour" })}
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
                    page?.title ?? t("auth.cgu_link", { defaultValue: "Conditions Générales d'Utilisation" })
                  )}
                </CardTitle>
                {page?.updatedAt ? (
                  <p className="text-xs text-muted-foreground mt-1">
                    {t("legal.updated_at", {
                      defaultValue: "Dernière mise à jour : {{date}}",
                      date: new Date(page.updatedAt).toLocaleString(),
                    })}
                  </p>
                ) : null}
              </div>
            </div>
          </CardHeader>
          <CardContent>
            {loading ? (
              <div className="space-y-2">
                <Skeleton className="h-4 w-full" />
                <Skeleton className="h-4 w-full" />
                <Skeleton className="h-4 w-3/4" />
              </div>
            ) : (
              <article className="prose prose-sm dark:prose-invert max-w-none whitespace-pre-wrap text-sm leading-relaxed">
                {page?.content ?? ""}
              </article>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
