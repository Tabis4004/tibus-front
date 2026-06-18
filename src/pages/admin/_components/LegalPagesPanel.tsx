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
  COMPANY_OWNER_CONTRACT_PATH,
  getCguPageSupabase,
  getCompanyOwnerContractPageSupabase,
  upsertCguPageSupabase,
  upsertCompanyOwnerContractPageSupabase,
  type LegalPage,
} from "@/lib/supabase/legal-pages.ts";

type LegalPageEditorProps = {
  slug: "cgu" | "company-owner-contract";
  titleKey: string;
  titleDefault: string;
  descKey: string;
  descDefault: string;
  previewPath: string;
  savedMessage: string;
};

async function loadLegalEditorPage(slug: LegalPageEditorProps["slug"]): Promise<LegalPage> {
  if (slug === "cgu") return getCguPageSupabase();
  return getCompanyOwnerContractPageSupabase();
}

async function saveLegalEditorPage(
  slug: LegalPageEditorProps["slug"],
  page: Omit<LegalPage, "slug">,
): Promise<LegalPage> {
  if (slug === "cgu") return upsertCguPageSupabase(page);
  return upsertCompanyOwnerContractPageSupabase(page);
}

function LegalPageEditor({
  slug,
  titleKey,
  titleDefault,
  descKey,
  descDefault,
  previewPath,
  savedMessage,
}: LegalPageEditorProps) {
  const { t } = useTranslation("admin");
  const { lng } = useParams<{ lng: string }>();
  const [page, setPage] = useState<LegalPage | null>(null);
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setLoading(true);
    void loadLegalEditorPage(slug)
      .then((data) => {
        setPage(data);
        setTitle(data.title);
        setContent(data.content);
      })
      .catch((err) => {
        toast.error(err instanceof Error ? err.message : t("legal_pages.load_error"));
      })
      .finally(() => setLoading(false));
  }, [slug, t]);

  const handleSave = async () => {
    setSaving(true);
    try {
      const saved = await saveLegalEditorPage(slug, { title: title.trim(), content });
      setPage(saved);
      setTitle(saved.title);
      setContent(saved.content);
      toast.success(savedMessage);
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
          {t(titleKey, { defaultValue: titleDefault })}
        </CardTitle>
        <p className="text-xs text-muted-foreground mt-1">
          {t(descKey, { defaultValue: descDefault })}
        </p>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="space-y-2">
          <Label>{t("legal_pages.page_title", { defaultValue: "Titre" })}</Label>
          <Input value={title} onChange={(e) => setTitle(e.target.value)} />
        </div>

        <div className="space-y-2">
          <Label>{t("legal_pages.page_content", { defaultValue: "Contenu" })}</Label>
          <Textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            rows={16}
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
            <Link
              to={`/${lng ?? "fr"}${previewPath}`}
              target="_blank"
              rel="noopener noreferrer"
              className="gap-2"
            >
              <ExternalLinkIcon className="w-4 h-4" />
              {t("legal_pages.preview", { defaultValue: "Voir la page" })} {previewPath}
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

export default function LegalPagesPanel() {
  const { t } = useTranslation("admin");

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold">
          {t("legal_pages.panel_title", { defaultValue: "Pages juridiques" })}
        </h2>
        <p className="text-sm text-muted-foreground mt-1">
          {t("legal_pages.panel_desc", {
            defaultValue:
              "Modifiez les textes affichés publiquement. Lien admin : /admin?tab=legal",
          })}
        </p>
      </div>

      <LegalPageEditor
        slug="cgu"
        titleKey="legal_pages.cgu_title"
        titleDefault="Conditions Générales d'Utilisation (CGU)"
        descKey="legal_pages.cgu_desc"
        descDefault="Contenu affiché sur /cgu et lié depuis l'inscription et la connexion."
        previewPath="/cgu"
        savedMessage={t("legal_pages.cgu_saved", { defaultValue: "CGU enregistrées" })}
      />

      <LegalPageEditor
        slug="company-owner-contract"
        titleKey="legal_pages.company_owner_title"
        titleDefault="Contrat propriétaire de compagnie"
        descKey="legal_pages.company_owner_desc"
        descDefault="Contrat obligatoire avant la mise en live. L'annexe technique reprend la section 2 de l'offre commerciale (/admin/commercial-offer)."
        previewPath={`/${COMPANY_OWNER_CONTRACT_PATH}`}
        savedMessage={t("legal_pages.company_owner_saved", {
          defaultValue: "Contrat propriétaire enregistré",
        })}
      />
    </div>
  );
}
