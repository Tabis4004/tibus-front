import { useCallback, useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { DownloadIcon, FileTextIcon, PrinterIcon, RotateCcwIcon, SaveIcon } from "lucide-react";
import { toast } from "sonner";
import {
  COMMERCIAL_OFFER_BLANK,
  cloneCommercialOfferDocument,
  type CommercialOfferDocument,
  type CommercialOfferField,
  type CommercialOfferModule,
  type CommercialOfferSection,
} from "@/data/commercial-offer-content.ts";
import {
  downloadCommercialOfferJson,
  downloadCommercialOfferPdf,
  downloadCommercialOfferWord,
} from "@/lib/commercial-offer-export.ts";
import {
  deleteCommercialOfferCustomizationSupabase,
  getCommercialOfferCustomizationSupabase,
  upsertCommercialOfferCustomizationSupabase,
} from "@/lib/supabase/commercial-offer-customization.ts";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import { cn } from "@/lib/utils.ts";

type CountryOption = { id: string; name: string };

function EditableField({
  field,
  onChange,
}: {
  field: CommercialOfferField;
  onChange: (value: string) => void;
}) {
  return (
    <div className="space-y-1.5">
      <Label className="text-sm">{field.label}</Label>
      <Input
        value={field.value ?? ""}
        onChange={(event) => onChange(event.target.value)}
        placeholder={COMMERCIAL_OFFER_BLANK}
      />
    </div>
  );
}

function EditableText({
  label,
  value,
  onChange,
  rows = 3,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  rows?: number;
}) {
  return (
    <div className="space-y-1.5">
      <Label className="text-sm">{label}</Label>
      <Textarea value={value} onChange={(event) => onChange(event.target.value)} rows={rows} />
    </div>
  );
}

function EditableStringList({
  items,
  onChange,
}: {
  items: string[];
  onChange: (items: string[]) => void;
}) {
  return (
    <div className="space-y-2">
      {items.map((item, index) => (
        <Textarea
          key={`${index}:${item.slice(0, 12)}`}
          value={item}
          onChange={(event) => {
            const next = [...items];
            next[index] = event.target.value;
            onChange(next);
          }}
          rows={2}
        />
      ))}
    </div>
  );
}

function EditableTable({
  headers,
  rows,
  onCellChange,
  lockedColumns = [],
}: {
  headers: string[];
  rows: string[][];
  onCellChange: (rowIndex: number, cellIndex: number, value: string) => void;
  lockedColumns?: number[];
}) {
  return (
    <div className="overflow-x-auto rounded-lg border">
      <table className="min-w-full text-sm">
        <thead className="bg-muted/60 text-left">
          <tr>
            {headers.map((header) => (
              <th key={header} className="px-3 py-2 font-medium whitespace-nowrap">
                {header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y">
          {rows.map((row, rowIndex) => (
            <tr key={rowIndex}>
              {row.map((cell, cellIndex) => (
                <td key={cellIndex} className="px-3 py-2 align-top">
                  {lockedColumns.includes(cellIndex) ? (
                    <span>{cell}</span>
                  ) : (
                    <Input
                      className="h-8 min-w-[120px]"
                      value={cell}
                      onChange={(event) => onCellChange(rowIndex, cellIndex, event.target.value)}
                      placeholder={COMMERCIAL_OFFER_BLANK}
                    />
                  )}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function ModulesEditor({
  modules,
  onChange,
  t,
}: {
  modules: CommercialOfferModule[];
  onChange: (modules: CommercialOfferModule[]) => void;
  t: (key: string, opts?: { defaultValue?: string; code?: string }) => string;
}) {
  return (
    <div className="overflow-x-auto rounded-lg border">
      <table className="min-w-full text-sm">
        <thead className="bg-muted/60 text-left">
          <tr>
            <th className="px-3 py-2 w-10">☐</th>
            <th className="px-3 py-2">{t("commercial_offer.module_code", { defaultValue: "Module" })}</th>
            <th className="px-3 py-2">{t("commercial_offer.module_title", { defaultValue: "Intitulé" })}</th>
            <th className="px-3 py-2">{t("commercial_offer.module_desc", { defaultValue: "Contenu fonctionnel" })}</th>
          </tr>
        </thead>
        <tbody className="divide-y">
          {modules.map((module, index) => (
            <tr key={module.code}>
              <td className="px-3 py-2">☐</td>
              <td className="px-3 py-2 font-medium">{module.code}</td>
              <td className="px-3 py-2">
                <Input
                  value={module.title}
                  onChange={(event) => {
                    const next = [...modules];
                    next[index] = { ...module, title: event.target.value };
                    onChange(next);
                  }}
                />
              </td>
              <td className="px-3 py-2">
                <Textarea
                  value={module.description}
                  onChange={(event) => {
                    const next = [...modules];
                    next[index] = { ...module, description: event.target.value };
                    onChange(next);
                  }}
                  rows={2}
                />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function OfferSectionEditor({
  section,
  onChange,
}: {
  section: CommercialOfferSection;
  onChange: (section: CommercialOfferSection) => void;
}) {
  return (
    <section className="space-y-3">
      <EditableText
        label={section.heading}
        value={section.heading}
        onChange={(heading) => onChange({ ...section, heading })}
        rows={1}
      />
      {section.paragraphs ? (
        <EditableStringList
          items={section.paragraphs}
          onChange={(paragraphs) => onChange({ ...section, paragraphs })}
        />
      ) : null}
      {section.bullets ? (
        <EditableStringList
          items={section.bullets}
          onChange={(bullets) => onChange({ ...section, bullets })}
        />
      ) : null}
    </section>
  );
}

export default function CommercialOfferDocumentPanel({
  locale,
  countryId,
  countryName,
  canSelectCountry = false,
  countries = [],
  onCountryChange,
}: {
  locale: string;
  countryId: string | null;
  countryName: string | null;
  canSelectCountry?: boolean;
  countries?: CountryOption[];
  onCountryChange?: (countryId: string) => void;
}) {
  const { t } = useTranslation("admin");
  const printRef = useRef<HTMLDivElement>(null);
  const [document, setDocument] = useState<CommercialOfferDocument | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [hasSavedCustomization, setHasSavedCustomization] = useState(false);
  const [isDirty, setIsDirty] = useState(false);

  const loadDocument = useCallback(async () => {
    if (!countryId) {
      setDocument(cloneCommercialOfferDocument(locale));
      setHasSavedCustomization(false);
      setIsDirty(false);
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const saved = await getCommercialOfferCustomizationSupabase(countryId, locale);
      setDocument(saved ?? cloneCommercialOfferDocument(locale));
      setHasSavedCustomization(Boolean(saved));
      setIsDirty(false);
    } catch (err) {
      setDocument(cloneCommercialOfferDocument(locale));
      setHasSavedCustomization(false);
      toast.error(err instanceof Error ? err.message : t("commercial_offer.load_error"));
    } finally {
      setLoading(false);
    }
  }, [countryId, locale, t]);

  useEffect(() => {
    void loadDocument();
  }, [loadDocument]);

  const patchDocument = (updater: (current: CommercialOfferDocument) => CommercialOfferDocument) => {
    setDocument((current) => {
      if (!current) return current;
      const next = updater(current);
      setIsDirty(true);
      return next;
    });
  };

  const handleSave = async () => {
    if (!document || !countryId) {
      toast.error(t("commercial_offer.country_required"));
      return;
    }
    setSaving(true);
    try {
      await upsertCommercialOfferCustomizationSupabase({
        countryId,
        locale,
        document,
      });
      setHasSavedCustomization(true);
      setIsDirty(false);
      toast.success(t("commercial_offer.saved"));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("commercial_offer.save_error"));
    } finally {
      setSaving(false);
    }
  };

  const handleReset = async () => {
    if (!countryId) return;
    setSaving(true);
    try {
      if (hasSavedCustomization) {
        await deleteCommercialOfferCustomizationSupabase(countryId, locale);
      }
      setDocument(cloneCommercialOfferDocument(locale));
      setHasSavedCustomization(false);
      setIsDirty(false);
      toast.success(t("commercial_offer.reset_done"));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("commercial_offer.save_error"));
    } finally {
      setSaving(false);
    }
  };

  if (loading || !document) {
    return <Skeleton className="h-96 w-full" />;
  }

  const exportCountryName = countryName ?? undefined;

  return (
    <div className="space-y-4">
      <Card className="print:hidden">
        <CardHeader className="flex flex-col gap-3">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <CardTitle className="text-base flex items-center gap-2">
                <FileTextIcon className="w-4 h-4" />
                {document.meta.title}
              </CardTitle>
              <p className="text-xs text-muted-foreground mt-1">{document.meta.subtitle}</p>
              <div className="flex flex-wrap gap-2 mt-2">
                {hasSavedCustomization ? (
                  <Badge variant="secondary">{t("commercial_offer.customized_badge")}</Badge>
                ) : (
                  <Badge variant="outline">{t("commercial_offer.default_badge")}</Badge>
                )}
                {isDirty ? <Badge variant="default">{t("commercial_offer.unsaved_badge")}</Badge> : null}
              </div>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button
                type="button"
                size="sm"
                className="gap-2"
                disabled={saving || !countryId || !isDirty}
                onClick={() => void handleSave()}
              >
                <SaveIcon className="w-4 h-4" />
                {t("commercial_offer.save")}
              </Button>
              <Button
                type="button"
                variant="outline"
                size="sm"
                className="gap-2"
                disabled={saving || !countryId}
                onClick={() => void handleReset()}
              >
                <RotateCcwIcon className="w-4 h-4" />
                {t("commercial_offer.reset")}
              </Button>
            </div>
          </div>

          {canSelectCountry && countries.length > 0 ? (
            <div className="space-y-1.5 max-w-sm">
              <Label>{t("commercial_offer.country_select")}</Label>
              <Select value={countryId ?? ""} onValueChange={(value) => onCountryChange?.(value)}>
                <SelectTrigger>
                  <SelectValue placeholder={t("commercial_offer.country_select")} />
                </SelectTrigger>
                <SelectContent>
                  {countries.map((country) => (
                    <SelectItem key={country.id} value={country.id}>
                      {country.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          ) : null}
        </CardHeader>
        <CardContent className="space-y-3">
          <p className="text-sm text-muted-foreground">
            {t("commercial_offer.editing_hint", { country: countryName ?? "—" })}
          </p>
          <div className="flex flex-wrap gap-2">
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="gap-2"
              onClick={() => {
                downloadCommercialOfferJson(document, locale, exportCountryName);
                toast.success(t("commercial_offer.export_json_done"));
              }}
            >
              <DownloadIcon className="w-4 h-4" />
              {t("commercial_offer.export_json")}
            </Button>
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="gap-2"
              onClick={() => {
                void downloadCommercialOfferPdf(document, locale, exportCountryName).then(() => {
                  toast.success(t("commercial_offer.export_pdf_done"));
                });
              }}
            >
              <DownloadIcon className="w-4 h-4" />
              {t("commercial_offer.export_pdf")}
            </Button>
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="gap-2"
              onClick={() => {
                downloadCommercialOfferWord(document, locale, exportCountryName);
                toast.success(t("commercial_offer.export_word_done"));
              }}
            >
              <DownloadIcon className="w-4 h-4" />
              {t("commercial_offer.export_word")}
            </Button>
            <Button type="button" variant="outline" size="sm" className="gap-2" onClick={() => window.print()}>
              <PrinterIcon className="w-4 h-4" />
              {t("commercial_offer.print")}
            </Button>
          </div>
          <p className="text-xs text-muted-foreground italic">{t("commercial_offer.restricted")}</p>
        </CardContent>
      </Card>

      <div ref={printRef} className={cn("space-y-8 print:space-y-6")}>
        <Card className="print:shadow-none print:border">
          <CardHeader>
            <CardTitle className="text-lg text-[#1A5296]">{document.letter.title}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid gap-3 md:grid-cols-2">
              {document.letter.fields.map((field) => (
                <EditableField
                  key={field.id}
                  field={field}
                  onChange={(value) =>
                    patchDocument((current) => ({
                      ...current,
                      letter: {
                        ...current.letter,
                        fields: current.letter.fields.map((row) =>
                          row.id === field.id ? { ...row, value } : row,
                        ),
                      },
                    }))
                  }
                />
              ))}
            </div>
            <EditableText
              label={t("commercial_offer.subject")}
              value={document.letter.subject}
              onChange={(subject) =>
                patchDocument((current) => ({ ...current, letter: { ...current.letter, subject } }))
              }
            />
            <EditableText
              label={t("commercial_offer.salutation", { defaultValue: "Formule d'appel" })}
              value={document.letter.salutation}
              onChange={(salutation) =>
                patchDocument((current) => ({ ...current, letter: { ...current.letter, salutation } }))
              }
              rows={1}
            />
            <EditableStringList
              items={document.letter.paragraphs}
              onChange={(paragraphs) =>
                patchDocument((current) => ({ ...current, letter: { ...current.letter, paragraphs } }))
              }
            />
            <EditableStringList
              items={document.letter.annexBullets}
              onChange={(annexBullets) =>
                patchDocument((current) => ({ ...current, letter: { ...current.letter, annexBullets } }))
              }
            />
            <EditableText
              label={t("commercial_offer.offline_note", { defaultValue: "Note guichet hors ligne" })}
              value={document.letter.offlineNote}
              onChange={(offlineNote) =>
                patchDocument((current) => ({ ...current, letter: { ...current.letter, offlineNote } }))
              }
            />
            <EditableText
              label={t("commercial_offer.closing", { defaultValue: "Formule de politesse" })}
              value={document.letter.closing}
              onChange={(closing) =>
                patchDocument((current) => ({ ...current, letter: { ...current.letter, closing } }))
              }
              rows={4}
            />
            <div className="grid gap-3 md:grid-cols-2">
              {document.letter.signatureFields.map((field) => (
                <EditableField
                  key={field.id}
                  field={field}
                  onChange={(value) =>
                    patchDocument((current) => ({
                      ...current,
                      letter: {
                        ...current.letter,
                        signatureFields: current.letter.signatureFields.map((row) =>
                          row.id === field.id ? { ...row, value } : row,
                        ),
                      },
                    }))
                  }
                />
              ))}
            </div>
          </CardContent>
        </Card>

        <Card className="print:shadow-none print:border print:break-before-page">
          <CardHeader>
            <EditableText
              label={t("commercial_offer.section_title", { defaultValue: "Titre section" })}
              value={document.technical.title}
              onChange={(title) =>
                patchDocument((current) => ({ ...current, technical: { ...current.technical, title } }))
              }
              rows={1}
            />
            <EditableText
              label={t("commercial_offer.section_subtitle", { defaultValue: "Sous-titre" })}
              value={document.technical.subtitle}
              onChange={(subtitle) =>
                patchDocument((current) => ({ ...current, technical: { ...current.technical, subtitle } }))
              }
              rows={1}
            />
          </CardHeader>
          <CardContent className="space-y-6">
            <div className="grid gap-3 md:grid-cols-2">
              {document.technical.fields.map((field) => (
                <EditableField
                  key={field.id}
                  field={field}
                  onChange={(value) =>
                    patchDocument((current) => ({
                      ...current,
                      technical: {
                        ...current.technical,
                        fields: current.technical.fields.map((row) =>
                          row.id === field.id ? { ...row, value } : row,
                        ),
                      },
                    }))
                  }
                />
              ))}
            </div>
            {document.technical.sections
              .filter((section) => section.id === "context")
              .map((section) => (
                <OfferSectionEditor
                  key={section.id}
                  section={section}
                  onChange={(nextSection) =>
                    patchDocument((current) => ({
                      ...current,
                      technical: {
                        ...current.technical,
                        sections: current.technical.sections.map((row) =>
                          row.id === section.id ? nextSection : row,
                        ),
                      },
                    }))
                  }
                />
              ))}
            <div className="space-y-2">
              <h3 className="text-base font-semibold text-[#1A5296]">
                {t("commercial_offer.architecture_heading")}
              </h3>
              <EditableTable
                headers={document.technical.architectureTable.headers}
                rows={document.technical.architectureTable.rows}
                lockedColumns={[0]}
                onCellChange={(rowIndex, cellIndex, value) =>
                  patchDocument((current) => {
                    const rows = current.technical.architectureTable.rows.map((row, index) =>
                      index === rowIndex
                        ? row.map((cell, colIndex) => (colIndex === cellIndex ? value : cell))
                        : row,
                    );
                    return {
                      ...current,
                      technical: {
                        ...current.technical,
                        architectureTable: {
                          ...current.technical.architectureTable,
                          rows,
                        },
                      },
                    };
                  })
                }
              />
            </div>
            <ModulesEditor
              modules={document.technical.modules}
              t={t}
              onChange={(modules) =>
                patchDocument((current) => ({
                  ...current,
                  technical: { ...current.technical, modules },
                }))
              }
            />
            {document.technical.sections
              .filter((section) => section.id !== "context")
              .map((section) => (
                <OfferSectionEditor
                  key={section.id}
                  section={section}
                  onChange={(nextSection) =>
                    patchDocument((current) => ({
                      ...current,
                      technical: {
                        ...current.technical,
                        sections: current.technical.sections.map((row) =>
                          row.id === section.id ? nextSection : row,
                        ),
                      },
                    }))
                  }
                />
              ))}
          </CardContent>
        </Card>

        <Card className="print:shadow-none print:border print:break-before-page">
          <CardHeader>
            <EditableText
              label={t("commercial_offer.section_title", { defaultValue: "Titre section" })}
              value={document.financial.title}
              onChange={(title) =>
                patchDocument((current) => ({ ...current, financial: { ...current.financial, title } }))
              }
              rows={1}
            />
            <EditableText
              label={t("commercial_offer.section_subtitle", { defaultValue: "Sous-titre" })}
              value={document.financial.subtitle}
              onChange={(subtitle) =>
                patchDocument((current) => ({ ...current, financial: { ...current.financial, subtitle } }))
              }
              rows={1}
            />
          </CardHeader>
          <CardContent className="space-y-6">
            <div className="grid gap-3 md:grid-cols-2">
              {document.financial.fields.map((field) => (
                <EditableField
                  key={field.id}
                  field={field}
                  onChange={(value) =>
                    patchDocument((current) => ({
                      ...current,
                      financial: {
                        ...current.financial,
                        fields: current.financial.fields.map((row) =>
                          row.id === field.id ? { ...row, value } : row,
                        ),
                      },
                    }))
                  }
                />
              ))}
            </div>
            <div className="space-y-2">
              <h3 className="text-base font-semibold text-[#1A5296]">{t("commercial_offer.pricing_heading")}</h3>
              <EditableTable
                headers={document.financial.modulePricingHeaders}
                rows={document.financial.modulePricingRows}
                lockedColumns={[0, 1]}
                onCellChange={(rowIndex, cellIndex, value) =>
                  patchDocument((current) => {
                    const rows = current.financial.modulePricingRows.map((row, index) =>
                      index === rowIndex
                        ? row.map((cell, colIndex) => (colIndex === cellIndex ? value : cell))
                        : row,
                    );
                    return {
                      ...current,
                      financial: { ...current.financial, modulePricingRows: rows },
                    };
                  })
                }
              />
            </div>
            <div className="space-y-2">
              <h3 className="text-base font-semibold text-[#1A5296]">{t("commercial_offer.pack_heading")}</h3>
              <EditableTable
                headers={document.financial.packTable.headers}
                rows={document.financial.packTable.rows}
                lockedColumns={[0]}
                onCellChange={(rowIndex, cellIndex, value) =>
                  patchDocument((current) => {
                    const rows = current.financial.packTable.rows.map((row, index) =>
                      index === rowIndex
                        ? row.map((cell, colIndex) => (colIndex === cellIndex ? value : cell))
                        : row,
                    );
                    return {
                      ...current,
                      financial: {
                        ...current.financial,
                        packTable: { ...current.financial.packTable, rows },
                      },
                    };
                  })
                }
              />
            </div>
            <div className="space-y-2">
              <h3 className="text-base font-semibold text-[#1A5296]">{t("commercial_offer.billing_heading")}</h3>
              <EditableStringList
                items={document.financial.billingBullets}
                onChange={(billingBullets) =>
                  patchDocument((current) => ({
                    ...current,
                    financial: { ...current.financial, billingBullets },
                  }))
                }
              />
            </div>
            <div className="space-y-2">
              <h3 className="text-base font-semibold text-[#1A5296]">{t("commercial_offer.summary_heading")}</h3>
              <EditableTable
                headers={document.financial.summaryTable.headers}
                rows={document.financial.summaryTable.rows}
                lockedColumns={[0]}
                onCellChange={(rowIndex, cellIndex, value) =>
                  patchDocument((current) => {
                    const rows = current.financial.summaryTable.rows.map((row, index) =>
                      index === rowIndex
                        ? row.map((cell, colIndex) => (colIndex === cellIndex ? value : cell))
                        : row,
                    );
                    return {
                      ...current,
                      financial: {
                        ...current.financial,
                        summaryTable: { ...current.financial.summaryTable, rows },
                      },
                    };
                  })
                }
              />
            </div>
            <EditableText
              label={t("commercial_offer.agreement_title", { defaultValue: "Bon pour accord" })}
              value={document.financial.agreementTitle}
              onChange={(agreementTitle) =>
                patchDocument((current) => ({
                  ...current,
                  financial: { ...current.financial, agreementTitle },
                }))
              }
              rows={1}
            />
            <div className="grid gap-3 md:grid-cols-2">
              {document.financial.agreementFields.map((field) => (
                <EditableField
                  key={field.id}
                  field={field}
                  onChange={(value) =>
                    patchDocument((current) => ({
                      ...current,
                      financial: {
                        ...current.financial,
                        agreementFields: current.financial.agreementFields.map((row) =>
                          row.id === field.id ? { ...row, value } : row,
                        ),
                      },
                    }))
                  }
                />
              ))}
            </div>
            <EditableText
              label={t("commercial_offer.footer_note", { defaultValue: "Note de bas de page" })}
              value={document.meta.footer}
              onChange={(footer) =>
                patchDocument((current) => ({ ...current, meta: { ...current.meta, footer } }))
              }
              rows={2}
            />
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
