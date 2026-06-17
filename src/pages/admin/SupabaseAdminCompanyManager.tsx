import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import {
  ArrowLeftIcon,
  BuildingIcon,
  BusIcon,
  LayoutDashboardIcon,
  MapPinIcon,
  UserPlusIcon,
  UsersIcon,
  RouteIcon,
} from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { supabase } from "@/lib/supabase";
import { updateCompanyRecruitedBySupabase } from "@/lib/supabase/accounting.ts";
import { listPlatformUsersForAdminSupabase, type PlatformAdminUserRow } from "@/lib/supabase/admin-users.ts";
import { useAppUser } from "@/hooks/use-app-user";
import { canManageCompanyFeatureModules } from "@/lib/auth/commercial-offer-access.ts";
import {
  isAdminPaysRole,
  isDemarcheurRole,
} from "@/lib/auth/company-access.ts";
import { enterSuperAdminOwnerCompanyContext } from "@/lib/supabase/owner-company.ts";
import { refreshOwnerCompanyContext } from "@/hooks/use-owner-company.tsx";
import AdminAccessGate from "./_components/AdminAccessGate.tsx";
import AdminAuditHub from "./_components/AdminAuditHub.tsx";
import CompanyFeatureModulesPanel from "./_components/CompanyFeatureModulesPanel.tsx";

type CompanyOverview = {
  id: string;
  name: string;
  managerName: string | null;
  isActive: boolean;
  countryId: string | null;
  countryName: string | null;
  recruitedByUserId: string | null;
  recruitedByName: string | null;
  busCount: number;
  stationCount: number;
  sellerCount: number;
};

export default function SupabaseAdminCompanyManager() {
  const { lng, companyId } = useParams<{ lng: string; companyId: string }>();
  const navigate = useNavigate();
  const { t } = useTranslation("common");
  const { isSuperAdmin, isReady, profile, roles, ownedCompanyIds } = useAppUser();
  const isAdminPays = isAdminPaysRole(roles);
  const isDemarcheur = isDemarcheurRole(roles);
  const canManageModules =
    Boolean(companyId) &&
    canManageCompanyFeatureModules(roles, isSuperAdmin, companyId ?? "", ownedCompanyIds);
  const canAccessCompanyAdmin =
    isSuperAdmin || isAdminPays || isDemarcheur || canManageModules;
  const [company, setCompany] = useState<CompanyOverview | null | undefined>(undefined);
  const [recruiterOptions, setRecruiterOptions] = useState<{ id: string; label: string }[]>([]);
  const [recruiterDraft, setRecruiterDraft] = useState<string>("__none");
  const [savingRecruiter, setSavingRecruiter] = useState(false);
  const [openingOwnerConsole, setOpeningOwnerConsole] = useState(false);

  useEffect(() => {
    if (isReady && !canAccessCompanyAdmin) {
      navigate(`/${lng ?? "fr"}`, { replace: true });
    }
  }, [isReady, canAccessCompanyAdmin, lng, navigate]);

  useEffect(() => {
    if (!companyId) return;
    let cancelled = false;

    void (async () => {
      const { data: row, error } = await supabase
        .from("Companies")
        .select("id, name, managerName, isActive, countryId, recruitedByUserId, Countries(name), recruitedBy:Users!Companies_recruitedByUserId_fkey(firstName, lastName, email)")
        .eq("id", companyId)
        .maybeSingle();

      if (error || !row) {
        if (!cancelled) setCompany(null);
        return;
      }

      const country = Array.isArray(row.Countries) ? row.Countries[0] : row.Countries;
      const countryId = (row.countryId as string | null) ?? null;
      const recruitedBy = Array.isArray(row.recruitedBy) ? row.recruitedBy[0] : row.recruitedBy;
      const recruitedByUserId = (row.recruitedByUserId as string | null) ?? null;
      const recruitedByName = recruitedBy
        ? `${(recruitedBy as { firstName?: string }).firstName ?? ""} ${(recruitedBy as { lastName?: string }).lastName ?? ""}`.trim()
          || (recruitedBy as { email?: string }).email
          || null
        : null;

      const [{ count: busCount }, { count: stationCount }, { data: roles }] = await Promise.all([
        supabase.from("Bus").select("id", { count: "exact", head: true }).eq("companyId", companyId),
        supabase.from("Gares").select("id", { count: "exact", head: true }).eq("companyId", companyId),
        supabase
          .from("UserRoles")
          .select("Role(name)")
          .eq("companyId", companyId),
      ]);

      const sellerCount = (roles ?? []).filter((r) => {
        const role = Array.isArray(r.Role) ? r.Role[0] : r.Role;
        const name = (role as { name?: string } | null)?.name;
        return name === "vendeur" || name === "controleur" || name === "comptable_compagnie";
      }).length;

      if (!cancelled) {
        if (
          !isSuperAdmin &&
          isAdminPays &&
          profile?.countryId &&
          countryId &&
          profile.countryId !== countryId
        ) {
          setCompany(null);
          return;
        }

        if (
          !isSuperAdmin &&
          isDemarcheur &&
          recruitedByUserId !== profile?.id
        ) {
          setCompany(null);
          return;
        }

        setCompany({
          id: row.id as string,
          name: row.name as string,
          managerName: (row.managerName as string | null) ?? null,
          isActive: Boolean(row.isActive),
          countryId,
          countryName: (country as { name?: string } | null)?.name ?? null,
          recruitedByUserId,
          recruitedByName: recruitedByName ?? null,
          busCount: busCount ?? 0,
          stationCount: stationCount ?? 0,
          sellerCount,
        });
        setRecruiterDraft(recruitedByUserId ?? "__none");
      }
    })().catch(() => {
      if (!cancelled) setCompany(null);
    });

    return () => {
      cancelled = true;
    };
  }, [companyId, isSuperAdmin, isAdminPays, isDemarcheur, profile?.countryId, profile?.id]);

  useEffect(() => {
    void listPlatformUsersForAdminSupabase(500)
      .then((users) => {
        setRecruiterOptions(
          users
            .filter((user: PlatformAdminUserRow) =>
              user.roles.some((role: string) =>
                ["vendeur_independant", "vendeur_master", "vendeur_reseau", "demarcheur", "master", "master_independant"].includes(role),
              ),
            )
            .map((user: PlatformAdminUserRow) => ({
              id: user.id,
              label: `${user.firstName} ${user.lastName}`.trim() || user.email || user.username,
            })),
        );
      })
      .catch(() => setRecruiterOptions([]));
  }, []);

  const handleOpenOwnerConsole = async () => {
    const appUserId = profile?.id;
    if (!company || !appUserId) return;
    setOpeningOwnerConsole(true);
    try {
      await enterSuperAdminOwnerCompanyContext(appUserId, company.id, {
        isSuperAdmin,
        ownedCompanyIds,
      });
      refreshOwnerCompanyContext();
      navigate(`/${lng ?? "fr"}/owner`);
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Impossible d'ouvrir la console owner.",
      );
    } finally {
      setOpeningOwnerConsole(false);
    }
  };

  const handleSaveRecruiter = async () => {
    if (!company) return;
    setSavingRecruiter(true);
    try {
      const userId = recruiterDraft === "__none" ? null : recruiterDraft;
      await updateCompanyRecruitedBySupabase(company.id, userId);
      const selected = recruiterOptions.find((option) => option.id === userId);
      setCompany((current) =>
        current
          ? {
              ...current,
              recruitedByUserId: userId,
              recruitedByName: selected?.label ?? null,
            }
          : current,
      );
      toast.success("Recruteur enregistré.");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Enregistrement impossible.");
    } finally {
      setSavingRecruiter(false);
    }
  };

  if (!companyId) return null;

  if (company === undefined) {
    return (
      <div className="max-w-4xl mx-auto px-4 py-8 space-y-6">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }

  if (!company) {
    return (
      <div className="max-w-4xl mx-auto px-4 py-16 text-center text-muted-foreground">
        Compagnie introuvable
      </div>
    );
  }

  return (
    <AdminAccessGate>
    <div className="max-w-4xl mx-auto px-4 py-6 space-y-6">
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="sm" asChild>
          <Link to={`/${lng ?? "fr"}/admin`}>
            <ArrowLeftIcon className="w-4 h-4 mr-1" />
            Admin
          </Link>
        </Button>
        <div>
          <h1 className="text-xl font-extrabold flex items-center gap-2">
            <BuildingIcon className="w-5 h-5 text-primary" />
            {company.name}
          </h1>
          <p className="text-sm text-muted-foreground">
            {company.managerName ?? "—"} · {company.countryName ?? "—"}
          </p>
        </div>
        <Badge variant={company.isActive ? "default" : "secondary"} className="ml-auto">
          {company.isActive ? t("status.active") : t("status.inactive")}
        </Badge>
        {canManageModules ? (
          <Badge variant="outline" className="hidden sm:inline-flex">
            Modules A–F
          </Badge>
        ) : null}
        {canManageModules ? (
          <Button
            type="button"
            size="sm"
            disabled={openingOwnerConsole}
            onClick={() => void handleOpenOwnerConsole()}
          >
            <LayoutDashboardIcon className="w-4 h-4 mr-1" />
            Gérer
          </Button>
        ) : null}
      </div>

      <CompanyFeatureModulesPanel companyId={company.id} readOnly={!canManageModules} />

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <BusIcon className="w-4 h-4" /> Bus
            </CardTitle>
          </CardHeader>
          <CardContent className="text-2xl font-bold">{company.busCount}</CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <MapPinIcon className="w-4 h-4" /> Gares
            </CardTitle>
          </CardHeader>
          <CardContent className="text-2xl font-bold">{company.stationCount}</CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2">
              <UsersIcon className="w-4 h-4" /> Équipe
            </CardTitle>
          </CardHeader>
          <CardContent className="text-2xl font-bold">{company.sellerCount}</CardContent>
        </Card>
      </div>

      {isSuperAdmin ? (
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <UserPlusIcon className="w-4 h-4" />
            Recruteur plateforme
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <p className="text-sm text-muted-foreground">
            Vendeur indépendant ou master ayant recruté cette compagnie pour Tibus. Utilisé pour le partage
            de commission « recruteur ».
          </p>
          <div className="space-y-1.5 max-w-md">
            <Label>Recruteur</Label>
            <Select value={recruiterDraft} onValueChange={setRecruiterDraft}>
              <SelectTrigger>
                <SelectValue placeholder="Aucun recruteur" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="__none">Aucun</SelectItem>
                {recruiterOptions.map((option) => (
                  <SelectItem key={option.id} value={option.id}>
                    {option.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          {company.recruitedByName ? (
            <p className="text-xs text-muted-foreground">Actuel : {company.recruitedByName}</p>
          ) : null}
          <Button size="sm" disabled={savingRecruiter} onClick={() => void handleSaveRecruiter()}>
            Enregistrer le recruteur
          </Button>
        </CardContent>
      </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <RouteIcon className="w-4 h-4" />
            Gestion avancée
          </CardTitle>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground space-y-3">
          <p>
            Ouvrez la console owner pour suivre l'activité opérationnelle : gares, bus, trajets,
            vendeurs et rapports.
          </p>
          <Button
            type="button"
            disabled={openingOwnerConsole}
            onClick={() => void handleOpenOwnerConsole()}
          >
            <LayoutDashboardIcon className="w-4 h-4 mr-1" />
            Gérer la compagnie
          </Button>
        </CardContent>
      </Card>

      <AdminAuditHub moduleKey="admin.companies" scopeLabel="companies" className="mt-2" />
    </div>
    </AdminAccessGate>
  );
}
