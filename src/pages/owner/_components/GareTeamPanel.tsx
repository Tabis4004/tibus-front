import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { MailIcon, TrashIcon, UserPlusIcon, UsersIcon } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog.tsx";
import {
  GARE_TEAM_ASSIGNABLE_ROLES,
  type GareTeamAssignableRole,
} from "@/lib/owner-team-roles.ts";
import {
  assignGareTeamRoleByEmailSupabase,
  listGareTeamMembersSupabase,
  removeGareTeamRoleSupabase,
  type GareTeamMember,
} from "@/lib/supabase/gare-team.ts";

const ROLE_LABEL_KEYS: Record<GareTeamAssignableRole, string> = {
  vendeur_gare: "gare.team_role_vendeur",
  controleur_gare: "gare.team_role_controleur",
  comptable_gare: "gare.team_role_comptable",
};

export default function GareTeamPanel({ gareId }: { gareId: string }) {
  const { t } = useTranslation("owner");
  const [members, setMembers] = useState<GareTeamMember[] | undefined>(undefined);
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<GareTeamAssignableRole>("vendeur_gare");
  const [assigning, setAssigning] = useState(false);
  const [removeTarget, setRemoveTarget] = useState<GareTeamMember | null>(null);

  const loadMembers = useCallback(async () => {
    setMembers(undefined);
    try {
      setMembers(await listGareTeamMembersSupabase(gareId));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("gare.team_load_error"));
      setMembers([]);
    }
  }, [gareId, t]);

  useEffect(() => {
    void loadMembers();
  }, [loadMembers]);

  const handleAssign = async () => {
    const trimmed = email.trim();
    if (!trimmed) return;
    setAssigning(true);
    try {
      const result = await assignGareTeamRoleByEmailSupabase({
        gareId,
        email: trimmed,
        roleName: role,
      });
      toast.success(t("gare.team_assigned", { name: result.name || trimmed }));
      setEmail("");
      void loadMembers();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("gare.team_assign_error"));
    } finally {
      setAssigning(false);
    }
  };

  const handleRemove = async () => {
    if (!removeTarget) return;
    try {
      await removeGareTeamRoleSupabase({
        gareId,
        userId: removeTarget.userId,
        roleName: removeTarget.roleName,
      });
      toast.success(t("gare.team_removed"));
      setRemoveTarget(null);
      void loadMembers();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("gare.team_remove_error"));
    }
  };

  return (
    <>
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <UsersIcon className="w-4 h-4" />
            {t("gare.team_title")}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-[1fr_auto_auto] sm:items-end">
            <div className="space-y-1.5">
              <Label htmlFor="gare-team-email">
                {t("gare.team_identifier", { defaultValue: "E-mail ou nom d'utilisateur" })}
              </Label>
              <Input
                id="gare-team-email"
                type="text"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder={t("gare.team_identifier_placeholder", {
                  defaultValue: "email@exemple.com ou username",
                })}
              />
            </div>
            <div className="space-y-1.5">
              <Label>{t("sellers.role")}</Label>
              <Select value={role} onValueChange={(v) => setRole(v as GareTeamAssignableRole)}>
                <SelectTrigger className="w-full sm:w-[180px]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {GARE_TEAM_ASSIGNABLE_ROLES.map((roleName) => (
                    <SelectItem key={roleName} value={roleName}>
                      {t(ROLE_LABEL_KEYS[roleName])}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <Button
              type="button"
              onClick={() => void handleAssign()}
              disabled={assigning || !email.trim()}
              className="sm:mb-0"
            >
              <UserPlusIcon className="w-4 h-4 mr-1.5" />
              {assigning ? t("sellers.assigning") : t("gare.team_add_btn")}
            </Button>
          </div>

          {members === undefined ? (
            <div className="space-y-2">
              {Array.from({ length: 2 }).map((_, i) => (
                <Skeleton key={i} className="h-14 rounded-lg" />
              ))}
            </div>
          ) : members.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t("gare.team_empty")}</p>
          ) : (
            <div className="space-y-2">
              {members.map((member) => (
                <div
                  key={`${member.userId}-${member.roleName}`}
                  className="flex items-center justify-between gap-3 rounded-lg border p-3"
                >
                  <div className="min-w-0">
                    <p className="font-medium text-sm truncate">
                      {member.firstName} {member.lastName}
                    </p>
                    {member.email ? (
                      <p className="text-xs text-muted-foreground flex items-center gap-1 truncate">
                        <MailIcon className="w-3 h-3 shrink-0" />
                        {member.email}
                      </p>
                    ) : null}
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <Badge variant="secondary">
                      {t(ROLE_LABEL_KEYS[member.roleName as GareTeamAssignableRole] ?? "sellers.role")}
                    </Badge>
                    <Button
                      type="button"
                      size="icon"
                      variant="ghost"
                      className="text-destructive"
                      onClick={() => setRemoveTarget(member)}
                    >
                      <TrashIcon className="w-4 h-4" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <AlertDialog open={Boolean(removeTarget)} onOpenChange={(open) => !open && setRemoveTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("gare.team_remove_confirm")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("gare.team_remove_desc", {
                name: removeTarget ? `${removeTarget.firstName} ${removeTarget.lastName}`.trim() : "",
              })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("buttons.cancel", { ns: "common" })}</AlertDialogCancel>
            <AlertDialogAction onClick={() => void handleRemove()}>
              {t("buttons.confirm", { ns: "common", defaultValue: "Confirmer" })}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
