import { useState } from "react";
import { useQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { useDebounce } from "@/hooks/use-debounce.ts";
import {
  UsersIcon, UserPlusIcon, TrashIcon, SearchIcon, MailIcon,
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription,
} from "@/components/ui/dialog.tsx";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog.tsx";
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent } from "@/components/ui/empty.tsx";

type SellerDoc = {
  _id: Id<"users">;
  name?: string;
  email?: string;
  avatar?: string;
};

function AddSellerDialog({ onClose }: { onClose: () => void }) {
  const { t } = useTranslation("owner");
  const [emailInput, setEmailInput] = useState("");
  const [debouncedEmail] = useDebounce(emailInput, 500);
  const assignSeller = useMutation(api.sellers.assignSeller);
  const [saving, setSaving] = useState(false);

  const found = useQuery(
    api.sellers.searchUserByEmail,
    debouncedEmail.length >= 3 ? { email: debouncedEmail } : "skip"
  );

  const handleAssign = async () => {
    if (!found) return;
    setSaving(true);
    try {
      await assignSeller({ userId: found._id });
      toast.success(t("sellers.assigned", { name: found.name ?? found.email }));
      onClose();
    } catch (err) {
      const msg = err instanceof Error ? err.message : t("sellers.remove_error");
      toast.error(msg);
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
                  <Avatar className="h-9 w-9">
                    <AvatarImage src={found.avatar} />
                    <AvatarFallback className="bg-primary/20 text-primary font-bold text-xs">
                      {found.name?.charAt(0) ?? "U"}
                    </AvatarFallback>
                  </Avatar>
                  <div className="flex-1 min-w-0">
                    <div className="font-semibold text-sm truncate">{found.name ?? "No name"}</div>
                    <div className="text-xs text-muted-foreground truncate">{found.email}</div>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
        <DialogFooter>
          <Button variant="secondary" onClick={onClose} disabled={saving}>{t("buttons.cancel", { ns: "common" })}</Button>
          <Button onClick={handleAssign} disabled={!found || saving}>
            {saving ? t("sellers.assigning") : t("sellers.add_as_seller")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export default function SellersManager() {
  const { t } = useTranslation("owner");
  const sellers = useQuery(api.sellers.listSellers, {});
  const removeSeller = useMutation(api.sellers.removeSeller);
  const [showAdd, setShowAdd] = useState(false);
  const [removeId, setRemoveId] = useState<Id<"users"> | null>(null);
  const removeTarget = sellers?.find((s) => s._id === removeId);

  const handleRemove = async () => {
    if (!removeId) return;
    try {
      await removeSeller({ userId: removeId });
      toast.success(t("sellers.removed"));
    } catch {
      toast.error(t("sellers.remove_error"));
    } finally {
      setRemoveId(null);
    }
  };

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">{t("sellers.title")}</h1>
          <p className="text-muted-foreground text-sm mt-0.5">{t("sellers.desc")}</p>
        </div>
        <Button size="sm" onClick={() => setShowAdd(true)} className="cursor-pointer">
          <UserPlusIcon className="w-4 h-4 mr-1.5" /> {t("sellers.add")}
        </Button>
      </div>

      {sellers === undefined ? (
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-16 rounded-xl" />)}
        </div>
      ) : sellers.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyMedia variant="icon"><UsersIcon /></EmptyMedia>
            <EmptyTitle>{t("sellers.no_sellers")}</EmptyTitle>
            <EmptyDescription>{t("sellers.no_sellers_desc")}</EmptyDescription>
          </EmptyHeader>
          <EmptyContent>
            <Button size="sm" onClick={() => setShowAdd(true)}>
              <UserPlusIcon className="w-4 h-4 mr-1.5" /> {t("sellers.add_first")}
            </Button>
          </EmptyContent>
        </Empty>
      ) : (
        <div className="space-y-3">
          {sellers.map((seller) => (
            <Card key={seller._id}>
              <CardContent className="p-4 flex items-center gap-4">
                <Avatar className="h-10 w-10 shrink-0">
                  <AvatarImage src={seller.avatar} />
                  <AvatarFallback className="bg-primary/15 text-primary font-bold text-sm">
                    {seller.name?.charAt(0) ?? "S"}
                  </AvatarFallback>
                </Avatar>
                <div className="flex-1 min-w-0">
                  <div className="font-semibold text-sm truncate">{seller.name ?? "No name"}</div>
                  <div className="text-xs text-muted-foreground truncate">{seller.email ?? "No email"}</div>
                </div>
                <Button
                  size="icon" variant="ghost"
                  className="h-8 w-8 cursor-pointer text-destructive hover:text-destructive shrink-0"
                  onClick={() => setRemoveId(seller._id as Id<"users">)}
                >
                  <TrashIcon className="w-3.5 h-3.5" />
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {showAdd && <AddSellerDialog onClose={() => setShowAdd(false)} />}

      <AlertDialog open={!!removeId} onOpenChange={() => setRemoveId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("sellers.remove_confirm")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("sellers.remove_desc", { name: removeTarget?.name ?? "This user" })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("buttons.cancel", { ns: "common" })}</AlertDialogCancel>
            <AlertDialogAction onClick={handleRemove} className="bg-destructive text-destructive-foreground hover:bg-destructive/90">
              {t("buttons.remove", { ns: "common" })}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
