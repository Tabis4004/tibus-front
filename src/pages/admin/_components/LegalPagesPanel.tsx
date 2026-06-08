import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { ExternalLinkIcon, FileTextIcon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  getCguPageSupabase,
  upsertCguPageSupabase,
  type LegalPage,
} from "@/lib/supabase/legal-pages.ts";

export default function LegalPagesPanel() {
  const { t } = useTranslation("admin");
  const { lng } = useParams<{ lng: string }>();
  const [page, setPage] = useState<LegalPage | null>(null);
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const load = () => {
    setLoading(true);
    void getCguPageSupabase()
      .then((data) => {
        setPage(data);
        setTitle(data.title);
        setContent(data.content);
      })
      .catch((err) => {
        toast.error(err instanceof Error ? err.message : t("legal_pages.load_error"));
      })
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, []);

  const handleSave = async () => {
    setSaving(true);
    try {
      const saved = await upsertCguPageSupabase({ title: title.trim(), content });
      setPage(saved);
      setTitle(saved.title);
      setContent(saved.content);
      toast.success(t("legal_pages.saved", { defaultValue: "CGU enregistrées" }));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("legal_pages.save_error"));
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <Card>
        <CardContent className="pt-6 space-y-3">
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-48 w-full" />
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <FileTextIcon className="w-4 h-4" />
          {t("legal_pages.cgu_title", { defaultValue: "Conditions Générales d'Utilisation (CGU)" })}
        </CardTitle>
        <p className="text-xs text-muted-foreground mt-1">
          {t("legal_pages.cgu_desc", {
            defaultValue: "Contenu affiché sur la page publique /cgu et lié depuis l'inscription et la connexion.",
          })}
        </p>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="space-y-2">
          <Label htmlFor="cgu-title">{t("legal_pages.page_title", { defaultValue: "Titre" })}</Label>
          <Input
            id="cgu-title"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
        </div>

        <div className="space-y-2">
          <Label htmlFor="cgu-content">{t("legal_pages.page_content", { defaultValue: "Contenu" })}</Label>
          <Textarea
            id="cgu-content"
            value={content}
            onChange={(e) => setContent(e.target.value)}
            rows={18}
            className="font-mono text-sm"
          />
        </div>

        <div className="flex flex-wrap gap-2">
          <Button onClick={() => void handleSave()} disabled={saving || !title.trim()}>
            {saving
              ? t("legal_pages.saving", { defaultValue: "Enregistrement…" })
              : t("legal_pages.save", { defaultValue: "Enregistrer" })}
          </Button>
          <Button asChild variant="outline">
            <Link to={`/${lng ?? "fr"}/cgu`} target="_blank" rel="noopener noreferrer" className="gap-2">
              <ExternalLinkIcon className="w-4 h-4" />
              {t("legal_pages.preview", { defaultValue: "Voir la page /cgu" })}
            </Link>
          </Button>
        </div>

        {page?.updatedAt ? (
          <p className="text-xs text-muted-foreground">
            {t("legal_pages.last_saved", {
              defaultValue: "Dernière sauvegarde : {{date}}",
              date: new Date(page.updatedAt).toLocaleString(),
            })}
          </p>
        ) : null}
      </CardContent>
    </Card>
  );
}
