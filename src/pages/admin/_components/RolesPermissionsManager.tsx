import { useState } from "react";
import { useTranslation } from "react-i18next";
import { KeyIcon } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Checkbox } from "@/components/ui/checkbox.tsx";
import { recordPlatformAuditSupabase } from "@/lib/supabase/platform-audit-log.ts";
import { updateRoleDroitsSupabase } from "@/lib/supabase/admin-users.ts";
import { DROIT_REGISTRY } from "@/lib/auth/droit-registry.ts";
import type { SupabaseRoleRow } from "../admin-data-loaders.ts";

type Props = {
  roles: SupabaseRoleRow[];
  onChanged: () => void;
};

// Écran super_admin uniquement (le tab "roles" n'est de toute façon jamais
// exposé aux autres rôles — voir visibleTabs dans SupabaseAdminPanel.tsx).
// Édite Role.droits en base via admin_update_role_droits(), qui alimente à
// son tour has_company_droit()/has_country_droit() côté RLS et hasDroit()
// côté front (useAppUser). Toggler un droit ici a donc un effet réel pour
// les droits marqués "Appliqué" (voir DROIT_REGISTRY.wired) ; les autres
// sont encore purement informatifs tant qu'aucune vérification ne les
// consulte ailleurs dans le code.
export default function RolesPermissionsManager({ roles, onChanged }: Props) {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");

  const [drafts, setDrafts] = useState<Record<string, string[]>>({});
  const [savingRole, setSavingRole] = useState<string | null>(null);

  const draftFor = (role: SupabaseRoleRow): string[] => drafts[role.name] ?? role.droits;

  const isDirty = (role: SupabaseRoleRow): boolean => {
    const draft = drafts[role.name];
    if (!draft) return false;
    const a = [...draft].sort();
    const b = [...role.droits].sort();
    return a.length !== b.length || a.some((v, i) => v !== b[i]);
  };

  const toggleDroit = (role: SupabaseRoleRow, droitKey: string, checked: boolean) => {
    const current = draftFor(role);
    const next = checked
      ? Array.from(new Set([...current, droitKey]))
      : current.filter((d) => d !== droitKey);
    setDrafts((prev) => ({ ...prev, [role.name]: next }));
  };

  const handleSave = async (role: SupabaseRoleRow) => {
    const draft = draftFor(role);
    setSavingRole(role.name);
    try {
      await updateRoleDroitsSupabase(role.name, draft);
      toast.success(t("permissions.updated", { defaultValue: "Permissions du rôle mises à jour." }));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.roles.permissions",
        action: "update",
        summary: `Permissions mises à jour pour le rôle ${role.name}`,
        metadata: { role: role.name, droits: draft },
      });
      setDrafts((prev) => {
        const next = { ...prev };
        delete next[role.name];
        return next;
      });
      onChanged();
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : t("permissions.update_error", { defaultValue: "Impossible de mettre à jour les permissions." }),
      );
    } finally {
      setSavingRole(null);
    }
  };

  if (roles.length === 0) {
    return (
      <div className="rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground">
        <KeyIcon className="mx-auto mb-2 h-6 w-6 opacity-50" />
        <p className="font-medium text-foreground">{t("roles.no_custom")}</p>
        <p className="mt-1">{t("roles.builtin_desc")}</p>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <p className="text-xs text-muted-foreground">
        {t("permissions.desc", {
          defaultValue: "Cochez ou décochez les droits accordés à chaque rôle. Réservé au super_admin.",
        })}
      </p>
      <div className="grid gap-3 md:grid-cols-2">
        {roles.map((role) => {
          const draft = draftFor(role);
          const dirty = isDirty(role);
          const saving = savingRole === role.name;
          return (
            <div key={role.id} className="rounded-xl border p-4 space-y-3">
              <div className="flex items-center justify-between gap-2">
                <p className="font-semibold">{tc(`roles.${role.name}`, { defaultValue: role.name })}</p>
                <div className="flex items-center gap-1">
                  <Badge variant={role.scope === "platform" ? "default" : "secondary"}>
                    {role.scope ?? "role"}
                  </Badge>
                  {role.isSystem ? (
                    <Badge variant="outline" className="text-[10px]">
                      {t("permissions.system_role", { defaultValue: "Rôle système" })}
                    </Badge>
                  ) : null}
                </div>
              </div>
              {role.description && (
                <p className="text-xs text-muted-foreground">{role.description}</p>
              )}
              <div className="grid gap-1.5 max-h-64 overflow-y-auto pr-1">
                {DROIT_REGISTRY.map((droit) => {
                  const checked = draft.includes(droit.key);
                  return (
                    <label
                      key={droit.key}
                      className="flex items-start gap-2 rounded-lg px-1.5 py-1 hover:bg-muted/50 cursor-pointer"
                      title={
                        droit.wired
                          ? undefined
                          : t("permissions.not_wired_hint", {
                              defaultValue:
                                "Ce droit n'est pas encore branché à une vérification d'accès réelle ailleurs dans l'app — le cocher/décocher ici n'a pas d'effet visible pour l'instant.",
                            })
                      }
                    >
                      <Checkbox
                        checked={checked}
                        disabled={saving}
                        onCheckedChange={(value) => toggleDroit(role, droit.key, value === true)}
                        className="mt-0.5"
                      />
                      <span className="min-w-0 flex-1">
                        <span className="flex items-center gap-1.5 flex-wrap">
                          <span className="text-sm">
                            {t(`permissions.droits.${droit.labelKey}`, { defaultValue: droit.key })}
                          </span>
                          {droit.wired ? (
                            <Badge variant="outline" className="text-[9px] px-1 py-0 text-emerald-600 border-emerald-600/30">
                              {t("permissions.wired_badge", { defaultValue: "Appliqué" })}
                            </Badge>
                          ) : (
                            <Badge variant="outline" className="text-[9px] px-1 py-0 text-muted-foreground">
                              {t("permissions.not_wired_badge", { defaultValue: "Informatif" })}
                            </Badge>
                          )}
                        </span>
                        <span className="block text-[11px] text-muted-foreground truncate">
                          {t(`permissions.droits.${droit.descKey}`, { defaultValue: "" })}
                        </span>
                      </span>
                    </label>
                  );
                })}
              </div>
              <div className="flex items-center justify-between gap-2 pt-1">
                {dirty ? (
                  <span className="text-[11px] text-amber-600">
                    {t("permissions.unsaved", { defaultValue: "Modifications non enregistrées" })}
                  </span>
                ) : (
                  <span />
                )}
                <Button
                  size="sm"
                  disabled={!dirty || saving}
                  onClick={() => void handleSave(role)}
                >
                  {saving ? t("permissions.saving", { defaultValue: "Enregistrement…" }) : t("permissions.save", { defaultValue: "Enregistrer" })}
                </Button>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
