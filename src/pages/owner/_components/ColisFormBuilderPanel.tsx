import { useEffect, useState } from "react";
import { toast } from "sonner";
import {
  ListChecksIcon,
  PlusIcon,
  SaveIcon,
  SlidersHorizontalIcon,
  TrashIcon,
} from "lucide-react";
import { errorMessage } from "@/lib/utils";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Switch } from "@/components/ui/switch.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogDescription,
} from "@/components/ui/dialog.tsx";
import {
  COLIS_BUILTIN_FORM_FIELDS,
  COLIS_REPORT_FIELD_REGISTRY,
  COLIS_REPORT_KEYS,
  COLIS_REPORT_LABELS,
  getCompanyColisSettingsSupabase,
  updateCompanyColisUiConfigSupabase,
  type ColisCustomField,
  type ColisCustomFieldType,
  type ColisReportKey,
  type ColisUiConfig,
} from "@/lib/supabase/colis-autonomes.ts";

const CUSTOM_FIELD_TYPE_LABELS: Record<ColisCustomFieldType, string> = {
  text: "Texte libre",
  number: "Nombre",
  select: "Liste déroulante",
  date: "Date",
  boolean: "Oui / Non",
};

function slugify(label: string): string {
  return label
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 40) || `champ_${Date.now()}`;
}

function AddCustomFieldDialog({
  onClose,
  onSave,
  existingKeys,
}: {
  onClose: () => void;
  onSave: (field: ColisCustomField) => void;
  existingKeys: string[];
}) {
  const [label, setLabel] = useState("");
  const [type, setType] = useState<ColisCustomFieldType>("text");
  const [optionsText, setOptionsText] = useState("");
  const [required, setRequired] = useState(false);

  const handleSave = () => {
    const trimmed = label.trim();
    if (!trimmed) return;
    let key = slugify(trimmed);
    let suffix = 2;
    while (existingKeys.includes(key)) {
      key = `${slugify(trimmed)}_${suffix}`;
      suffix += 1;
    }
    const options = type === "select"
      ? optionsText.split("\n").map((o) => o.trim()).filter(Boolean)
      : undefined;
    if (type === "select" && (!options || options.length === 0)) {
      toast.error("Renseignez au moins une option pour une liste déroulante.");
      return;
    }
    onSave({ key, label: trimmed, type, options, required });
    onClose();
  };

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Ajouter un champ</DialogTitle>
          <DialogDescription>
            Ce champ apparaîtra sur le formulaire d'enregistrement colis (courrier_mobile et web).
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label>Nom du champ</Label>
            <Input value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Ex: Référence client" />
          </div>
          <div className="space-y-1.5">
            <Label>Type de valeur</Label>
            <Select value={type} onValueChange={(v) => setType(v as ColisCustomFieldType)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {(Object.entries(CUSTOM_FIELD_TYPE_LABELS) as [ColisCustomFieldType, string][]).map(
                  ([value, l]) => (
                    <SelectItem key={value} value={value}>
                      {l}
                    </SelectItem>
                  ),
                )}
              </SelectContent>
            </Select>
          </div>
          {type === "select" ? (
            <div className="space-y-1.5">
              <Label>Options (une par ligne)</Label>
              <Textarea
                rows={4}
                value={optionsText}
                onChange={(e) => setOptionsText(e.target.value)}
                placeholder={"Normal\nUrgent"}
              />
            </div>
          ) : null}
          <div className="flex items-center justify-between">
            <Label>Champ obligatoire</Label>
            <Switch checked={required} onCheckedChange={setRequired} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="secondary" onClick={onClose}>
            Annuler
          </Button>
          <Button onClick={handleSave} disabled={!label.trim()}>
            Ajouter
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export default function ColisFormBuilderPanel({ companyId }: { companyId: string }) {
  const [config, setConfig] = useState<ColisUiConfig | null>(null);
  const [saving, setSaving] = useState(false);
  const [dirty, setDirty] = useState(false);
  const [showAddField, setShowAddField] = useState(false);

  const load = async () => {
    setConfig(null);
    try {
      const settings = await getCompanyColisSettingsSupabase(companyId);
      setConfig(settings.uiConfig);
      setDirty(false);
    } catch (err) {
      toast.error(errorMessage(err, "Chargement impossible"));
    }
  };

  useEffect(() => {
    void load();
  }, [companyId]);

  const handleSave = async () => {
    if (!config) return;
    setSaving(true);
    try {
      const updated = await updateCompanyColisUiConfigSupabase(companyId, config);
      setConfig(updated.uiConfig);
      setDirty(false);
      toast.success("Configuration enregistrée");
    } catch (err) {
      toast.error(errorMessage(err, "Enregistrement impossible"));
    } finally {
      setSaving(false);
    }
  };

  if (!config) {
    return <Skeleton className="h-72 w-full" />;
  }

  const toggleFormField = (key: string, visible: boolean) => {
    setConfig({ ...config, formFields: { ...config.formFields, [key]: visible } });
    setDirty(true);
  };

  const isFormFieldVisible = (key: string) => config.formFields[key] !== false;

  const addCustomField = (field: ColisCustomField) => {
    setConfig({ ...config, customFields: [...config.customFields, field] });
    setDirty(true);
  };

  const removeCustomField = (key: string) => {
    setConfig({ ...config, customFields: config.customFields.filter((f) => f.key !== key) });
    setDirty(true);
  };

  const toggleReportEnabled = (key: ColisReportKey, enabled: boolean) => {
    setConfig({
      ...config,
      reports: { ...config.reports, [key]: { ...config.reports[key], enabled } },
    });
    setDirty(true);
  };

  const toggleReportField = (key: ColisReportKey, fieldKey: string, visible: boolean) => {
    const current = config.reports[key];
    const hiddenFields = visible
      ? current.hiddenFields.filter((f) => f !== fieldKey)
      : [...current.hiddenFields.filter((f) => f !== fieldKey), fieldKey];
    setConfig({ ...config, reports: { ...config.reports, [key]: { ...current, hiddenFields } } });
    setDirty(true);
  };

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-bold flex items-center gap-2">
          <SlidersHorizontalIcon className="w-4 h-4" />
          Formulaire colis &amp; rapports
        </h2>
        <p className="text-sm text-muted-foreground mt-1">
          Personnalisez le formulaire d'enregistrement (champs affichés, champs ajoutés) et la
          visibilité des rapports pour votre compagnie — appliqué sur l'app agent (courrier_mobile)
          et sur le web.
        </p>
      </div>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">Champs du formulaire</CardTitle>
          <p className="text-xs text-muted-foreground">
            Masquez les champs natifs non utilisés par votre compagnie.
          </p>
        </CardHeader>
        <CardContent className="space-y-2">
          {COLIS_BUILTIN_FORM_FIELDS.map((f) => (
            <div key={f.key} className="flex items-center justify-between gap-3 py-1">
              <Label className="font-normal">{f.label}</Label>
              <Switch
                checked={isFormFieldVisible(f.key)}
                onCheckedChange={(v) => toggleFormField(f.key, v)}
              />
            </div>
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between gap-3">
            <div>
              <CardTitle className="text-base flex items-center gap-2">
                <ListChecksIcon className="w-4 h-4" />
                Champs personnalisés
              </CardTitle>
              <p className="text-xs text-muted-foreground mt-1">
                Ajoutez vos propres champs (texte, nombre, liste, date, oui/non).
              </p>
            </div>
            <Button size="sm" className="cursor-pointer gap-1.5 shrink-0" onClick={() => setShowAddField(true)}>
              <PlusIcon className="w-3.5 h-3.5" />
              Ajouter
            </Button>
          </div>
        </CardHeader>
        <CardContent className="space-y-2">
          {config.customFields.length === 0 ? (
            <p className="text-sm text-muted-foreground">Aucun champ personnalisé.</p>
          ) : (
            config.customFields.map((f) => (
              <div key={f.key} className="rounded-lg border px-3 py-2 flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-sm font-medium truncate">
                    {f.label}
                    {f.required ? " *" : ""}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    {CUSTOM_FIELD_TYPE_LABELS[f.type]}
                    {f.options?.length ? ` · ${f.options.join(", ")}` : ""}
                  </p>
                </div>
                <Button
                  size="icon"
                  variant="ghost"
                  className="text-destructive cursor-pointer shrink-0"
                  onClick={() => removeCustomField(f.key)}
                >
                  <TrashIcon className="w-4 h-4" />
                </Button>
              </div>
            ))
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">Visibilité des rapports</CardTitle>
          <p className="text-xs text-muted-foreground">
            Masquez un rapport entier, ou gardez-le visible en masquant seulement certaines
            données sensibles (ex. pas de montant global sur le bordereau).
          </p>
        </CardHeader>
        <CardContent className="space-y-4">
          {COLIS_REPORT_KEYS.map((key) => {
            const report = config.reports[key];
            const fields = COLIS_REPORT_FIELD_REGISTRY[key];
            return (
              <div key={key} className="rounded-lg border px-3 py-3 space-y-2">
                <div className="flex items-center justify-between gap-3">
                  <Label className="font-semibold">{COLIS_REPORT_LABELS[key]}</Label>
                  <Switch
                    checked={report.enabled}
                    onCheckedChange={(v) => toggleReportEnabled(key, v)}
                  />
                </div>
                {report.enabled && fields.length > 0 ? (
                  <div className="pt-2 border-t space-y-1.5">
                    <p className="text-[11px] text-muted-foreground">
                      Données visibles dans ce rapport :
                    </p>
                    {fields.map((f) => (
                      <div key={f.key} className="flex items-center justify-between gap-3">
                        <Label className="text-xs font-normal text-muted-foreground">{f.label}</Label>
                        <Switch
                          className="scale-90"
                          checked={!report.hiddenFields.includes(f.key)}
                          onCheckedChange={(v) => toggleReportField(key, f.key, v)}
                        />
                      </div>
                    ))}
                  </div>
                ) : null}
              </div>
            );
          })}
        </CardContent>
      </Card>

      <Button className="cursor-pointer gap-2" disabled={!dirty || saving} onClick={() => void handleSave()}>
        <SaveIcon className="w-4 h-4" />
        {saving ? "…" : "Enregistrer"}
      </Button>

      {showAddField ? (
        <AddCustomFieldDialog
          onClose={() => setShowAddField(false)}
          onSave={addCustomField}
          existingKeys={config.customFields.map((f) => f.key)}
        />
      ) : null}
    </div>
  );
}
