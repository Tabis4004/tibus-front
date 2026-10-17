import { useEffect, useState } from "react";
import { CalendarClockIcon } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import {
  type AppSubscription,
  type AppSubscriptionKey,
  getCompanyAppSubscriptionsSupabase,
  setCompanyAppSubscriptionSupabase,
} from "@/lib/supabase/app-subscriptions.ts";

const APPS: { key: AppSubscriptionKey; label: string }[] = [
  { key: "courrier", label: "Courrier (app courrier)" },
  { key: "embarquement", label: "Embarquement" },
  { key: "comptabilite", label: "Comptabilité (dépenses + bilan SYSCOHADA)" },
];

type Props = { companyId: string; readOnly?: boolean };

/**
 * Dates de fin d'abonnement par application (migration 222). Après la date,
 * l'application passe en lecture seule ; le owner est prévenu un mois avant.
 * Champ vide + Enregistrer = illimité.
 */
export default function CompanyAppSubscriptionsPanel({ companyId, readOnly = false }: Props) {
  const [subs, setSubs] = useState<AppSubscription[]>([]);
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState<string | null>(null);

  const load = () =>
    getCompanyAppSubscriptionsSupabase(companyId)
      .then((rows) => {
        setSubs(rows);
        const next: Record<string, string> = {};
        for (const r of rows) next[r.appKey] = r.endDate ? r.endDate.slice(0, 10) : "";
        setDrafts(next);
      })
      .catch((e: unknown) => toast.error(e instanceof Error ? e.message : String(e)));

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [companyId]);

  const save = async (key: AppSubscriptionKey) => {
    setSaving(key);
    try {
      const day = drafts[key];
      await setCompanyAppSubscriptionSupabase(companyId, key, day ? `${day}T23:59:59` : null);
      toast.success("Abonnement enregistré");
      await load();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(null);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base">
          <CalendarClockIcon className="size-4" /> Abonnements des applications
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {APPS.map((app) => {
          const current = subs.find((s) => s.appKey === app.key);
          return (
            <div key={app.key} className="flex flex-wrap items-end gap-2">
              <div className="min-w-56 flex-1">
                <Label className="text-sm">{app.label}</Label>
                <p className="text-xs text-muted-foreground">
                  {current
                    ? current.endDate
                      ? `${current.state === "expired" ? "Expiré" : "Jusqu'au"} ${new Date(current.endDate).toLocaleDateString("fr-FR")}`
                      : "Illimité"
                    : "Aucune date (pas de restriction)"}
                </p>
              </div>
              <Input
                type="date"
                className="w-44"
                disabled={readOnly}
                value={drafts[app.key] ?? ""}
                onChange={(e) => setDrafts((d) => ({ ...d, [app.key]: e.target.value }))}
              />
              <Button size="sm" disabled={readOnly || saving === app.key} onClick={() => void save(app.key)}>
                Enregistrer
              </Button>
            </div>
          );
        })}
      </CardContent>
    </Card>
  );
}
