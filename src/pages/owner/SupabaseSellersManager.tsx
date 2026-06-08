import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { useDebounce } from "@/hooks/use-debounce.ts";
import {
  UsersIcon,
  UserPlusIcon,
  TrashIcon,
  SearchIcon,
  MailIcon,
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogDescription,
} from "@/components/ui/dialog.tsx";
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
  Empty,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
  EmptyDescription,
  EmptyContent,
} from "@/components/ui/empty.tsx";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import {
  listOwnerSellersSupabase,
  findAssignableCompanyUserByEmailSupabase,
  assignCompanySellerByEmailSupabase,
  removeCompanySellerSupabase,
  type SupabaseOwnerSeller,
  type OwnerTeamRoleName,
} from "@/lib/supabase/owner-operations";

const ROLE_LABELS: Record<OwnerTeamRoleName, string> = {
  vendeur: "Vendeur",
  controleur: "Contrôleur",
  comptable_compagnie: "Comptable",
};

function AddSellerDialog({
  onClose,
  onSaved,
}: {
  onClose: () => void;
  onSaved: () => void;
}) {
  const { t } = useTranslation("owner");
  const [emailInput, setEmailInput] = useState("");
  const [roleName, setRoleName] = useState<OwnerTeamRoleName>("vendeur");
  const [debouncedEmail] = useDebounce(emailInput, 500);
  const [found, setFound] = useState<
    { id: string; name: string; email: string | null } | null | undefined
  >(undefined);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (debouncedEmail.length < 3) {
      setFound(undefined);
      return;
    }
    let cancelled = false;
    setFound(undefined);
    void findAssignableCompanyUserByEmailSupabase(debouncedEmail)
      .then((user) => {
        if (!cancelled) setFound(user);
      })
      .catch(() => {
        if (!cancelled) setFound(null);
      });
    return () => {
      cancelled = true;
    };
  }, [debouncedEmail]);

  const handleAssign = async () => {
    if (!found) return;
    setSaving(true);
    try {
      await assignCompanySellerByEmailSupabase({ email: emailInput, roleName });
      toast.success(t("sellers.assigned", { name: found.name ?? found.email }));
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("sellers.remove_error"));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>{t("sellers.add_title")}</DialogTitle>
          <DialogDescription>{t("sellers.add_desc")}</DialogDescription>
        </DialogHeader>
        <div className="space-y-4 py-1">
          <div className="relative">
            <SearchIcon className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input
              placeholder={t("sellers.search_email")}
              className="pl-9"
              value={emailInput}
              onChange={(e) => setEmailInput(e.target.value)}
            />
          </div>
          <div className="space-y-1.5">
            <Select
              value={roleName}
              onValueChange={(v) => setRoleName(v as OwnerTeamRoleName)}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {(Object.keys(ROLE_LABELS) as OwnerTeamRoleName[]).map((role) => (
                  <SelectItem key={role} value={role}>
                    {ROLE_LABELS[role]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          {debouncedEmail.length >= 3 && (
            <div>
              {found === undefined ? (
                <Skeleton className="h-14 rounded-xl" />
              ) : found === null ? (
                <div className="flex items-center gap-3 p-3 rounded-xl bg-muted text-sm text-muted-foreground">
                  <MailIcon className="w-4 h-4 shrink-0" />
                  {t("sellers.no_user")}
                </div>
              ) : (
                <div className="flex items-center gap-3 p-3 rounded-xl bg-muted">
                  <div className="flex-1 min-w-0">
                    <div className="font-semibold text-sm truncate">{found.name}</div>
                    <div className="text-xs text-muted-foreground truncate">
                      {found.email}
                    </div>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
        <DialogFooter>
          <Button variant="secondary" onClick={onClose} disabled={saving}>
            {t("buttons.cancel", { ns: "common" })}
          </Button>
          <Button onClick={handleAssign} disabled={!found || saving}>
            {saving ? t("sellers.assigning") : t("sellers.add_as_seller")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export default function SupabaseSellersManager() {
  const { t } = useTranslation("owner");
  const { appUserId } = useSupabaseAuth();
  const [sellers, setSellers] = useState<SupabaseOwnerSeller[] | undefined>(undefined);
  const [showAdd, setShowAdd] = useState(false);
  const [removeTarget, setRemoveTarget] = useState<SupabaseOwnerSeller | null>(null);

  const loadData = useCallback(async () => {
    if (!appUserId) return;
    setSellers(undefined);
    try {
      setSellers(await listOwnerSellersSupabase(appUserId));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("sellers.remove_error"));
      setSellers([]);
    }
  }, [appUserId, t]);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  const handleRemove = async () => {
    if (!removeTarget || !appUserId) return;
    try {
      await removeCompanySellerSupabase(
        appUserId,
        removeTarget.id,
        removeTarget.roleName,
      );
      toast.success(t("sellers.removed"));
      void loadData();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("sellers.remove_error"));
    } finally {
      setRemoveTarget(null);
    }
  };

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">{t("sellers.title")}</h1>
          <p className="text-muted-foreground text-sm mt-0.5">{t("sellers.desc")}</p>
        </div>
        <Button size="sm" onClick={() => setShowAdd(true)}>
          <UserPlusIcon className="w-4 h-4 mr-1.5" /> {t("sellers.add")}
        </Button>
      </div>

      {sellers === undefined ? (
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-16 rounded-xl" />
          ))}
        </div>
      ) : sellers.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon">
              <UsersIcon />
            </EmptyMedia>
            <EmptyTitle>{t("sellers.no_sellers")}</EmptyTitle>
            <EmptyDescription>{t("sellers.no_sellers_desc")}</EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <Button size="sm" onClick={() => setShowAdd(true)}>
              {t("sellers.add_first")}
            </Button>
          </EmptyContent>
        </Empty>
      ) : (
        <div className="space-y-3">
          {sellers.map((seller) => (
            <Card key={`${seller.id}-${seller.roleName}`}>
              <CardContent className="p-4 flex items-center gap-4">
                <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center shrink-0 font-bold text-primary text-sm">
                  {seller.name.charAt(0).toUpperCase()}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="font-semibold text-sm truncate">{seller.name}</div>
                  <div className="text-xs text-muted-foreground truncate">
                    {seller.email ?? "—"}
                  </div>
                </div>
                <Badge variant="secondary" className="text-[10px] shrink-0">
                  {ROLE_LABELS[seller.roleName]}
                </Badge>
                <Button
                  size="icon"
                  variant="ghost"
                  className="h-8 w-8 text-destructive hover:text-destructive shrink-0"
                  onClick={() => setRemoveTarget(seller)}
                >
                  <TrashIcon className="w-3.5 h-3.5" />
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {showAdd && (
        <AddSellerDialog onClose={() => setShowAdd(false)} onSaved={() => void loadData()} />
      )}

      <AlertDialog open={!!removeTarget} onOpenChange={() => setRemoveTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("sellers.remove_confirm")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("sellers.remove_desc", { name: removeTarget?.name })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("buttons.cancel", { ns: "common" })}</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleRemove}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {t("buttons.remove", { ns: "common" })}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
