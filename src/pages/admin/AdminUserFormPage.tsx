import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import {
  ArrowLeftIcon,
  ShieldIcon,
  UserPlusIcon,
} from "lucide-react";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { supabase } from "@/lib/supabase";
import {
  adminAssignUserRoleSupabase,
  adminRemoveUserRoleSupabase,
  isCompanyScopedRole,
  listUserRoleAssignmentsSupabase,
  provisionUserSupabase,
  roleAssignmentKey,
  type UserRoleAssignment,
} from "@/lib/supabase/user-management.ts";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Checkbox } from "@/components/ui/checkbox.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import AdminAccessGate from "./_components/AdminAccessGate.tsx";
import AdminAuditHub from "./_components/AdminAuditHub.tsx";
import { recordPlatformAuditSupabase } from "@/lib/supabase/platform-audit-log.ts";

type RoleRow = { id: string; name: string; scope: string | null; description: string | null };
type CompanyRow = { id: string; name: string };
type CountryRow = { id: string; name: string };

const ASSIGNABLE_ROLES = [
  "super_admin",
  "admin_pays",
  "master",
  "master_independant",
  "vendeur_master",
  "vendeur_reseau",
  "vendeur_independant",
  "owner",
  "comptable_compagnie",
  "controleur",
  "vendeur",
] as const;

export default function AdminUserFormPage() {
  const { t: tc } = useTranslation("common");
  const { t } = useTranslation("admin");
  const { lng, userId } = useParams<{ lng: string; userId?: string }>();
  const navigate = useNavigate();
  const appUser = useAppUser();
  const isEdit = Boolean(userId);

  const [loading, setLoading] = useState(isEdit);
  const [saving, setSaving] = useState(false);
  const [roles, setRoles] = useState<RoleRow[]>([]);
  const [companies, setCompanies] = useState<CompanyRow[]>([]);
  const [countries, setCountries] = useState<CountryRow[]>([]);

  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [companyId, setCompanyId] = useState("");
  const [countryId, setCountryId] = useState("");
  const [selectedRoles, setSelectedRoles] = useState<string[]>([]);
  const [initialAssignments, setInitialAssignments] = useState<UserRoleAssignment[]>([]);

  const base = `/${lng ?? "fr"}`;

  useEffect(() => {
    if (appUser.isReady && !appUser.isSuperAdmin) {
      navigate(base, { replace: true });
    }
  }, [appUser.isReady, appUser.isSuperAdmin, base, navigate]);

  useEffect(() => {
    let cancelled = false;

    void (async () => {
      try {
        const [rolesRes, companiesRes, countriesRes] = await Promise.all([
          supabase.from("Role").select("id, name, scope, description").order("level", { ascending: false }),
          supabase.from("Companies").select("id, name").order("name"),
          supabase.from("Countries").select("id, name").order("name"),
        ]);

        if (rolesRes.error) throw rolesRes.error;
        if (companiesRes.error) throw companiesRes.error;
        if (countriesRes.error) throw countriesRes.error;

        if (cancelled) return;

        setRoles(
          (rolesRes.data ?? []).filter((r) =>
            ASSIGNABLE_ROLES.includes(r.name as (typeof ASSIGNABLE_ROLES)[number]),
          ) as RoleRow[],
        );
        setCompanies((companiesRes.data ?? []) as CompanyRow[]);
        setCountries((countriesRes.data ?? []) as CountryRow[]);

        if (isEdit && userId) {
          const { data: userRow, error: userError } = await supabase
            .from("Users")
            .select("id, firstName, lastName, email, phone")
            .eq("id", userId)
            .maybeSingle();
          if (userError) throw userError;
          if (!userRow) throw new Error(t("users.not_found", { defaultValue: "Utilisateur introuvable" }));

          const assignments = await listUserRoleAssignmentsSupabase(userId);
          if (cancelled) return;

          setFirstName(userRow.firstName as string);
          setLastName(userRow.lastName as string);
          setEmail((userRow.email as string | null) ?? "");
          setPhone((userRow.phone as string | null) ?? "");
          setInitialAssignments(assignments);
          setSelectedRoles(
            assignments
              .map((a) => a.roleName)
              .filter((name) => name !== "traveler" && ASSIGNABLE_ROLES.includes(name as (typeof ASSIGNABLE_ROLES)[number])),
          );

          const companyScoped = assignments.find((a) => a.companyId);
          if (companyScoped?.companyId) setCompanyId(companyScoped.companyId);
          const countryScoped = assignments.find((a) => a.roleName === "admin_pays" && a.countryId);
          if (countryScoped?.countryId) setCountryId(countryScoped.countryId);
        }
      } catch (err) {
        if (!cancelled) {
          toast.error(err instanceof Error ? err.message : t("users.save_error"));
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [isEdit, userId, t]);

  const needsCompany = useMemo(
    () => selectedRoles.some((r) => isCompanyScopedRole(r)),
    [selectedRoles],
  );
  const needsCountry = useMemo(() => selectedRoles.includes("admin_pays"), [selectedRoles]);

  const toggleRole = (roleName: string, checked: boolean) => {
    setSelectedRoles((prev) =>
      checked ? [...new Set([...prev, roleName])] : prev.filter((r) => r !== roleName),
    );
  };

  const handleCreate = async () => {
    if (!selectedRoles.length) {
      toast.error(t("users.roles_required"));
      return;
    }
    if (needsCompany && !companyId) {
      toast.error(t("users.company_required"));
      return;
    }
    if (needsCountry && !countryId) {
      toast.error(t("users.country_required"));
      return;
    }

    setSaving(true);
    try {
      await provisionUserSupabase({
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        email: email.trim(),
        phone: phone.trim() || undefined,
        password,
        roles: selectedRoles,
        companyId: needsCompany ? companyId : undefined,
        countryId: needsCountry ? countryId : undefined,
      });
      toast.success(t("users.created"));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.users",
        action: "create",
        summary: `Utilisateur créé : ${email.trim()}`,
        metadata: { roles: selectedRoles },
      });
      navigate(`${base}/admin?tab=users`, { replace: true });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("users.save_error"));
    } finally {
      setSaving(false);
    }
  };

  const handleEdit = async () => {
    if (!userId || !selectedRoles.length) {
      toast.error(t("users.roles_required"));
      return;
    }
    if (needsCompany && !companyId) {
      toast.error(t("users.company_required"));
      return;
    }
    if (needsCountry && !countryId) {
      toast.error(t("users.country_required"));
      return;
    }

    setSaving(true);
    try {
      const desired = new Set(
        selectedRoles.map((roleName) =>
          roleAssignmentKey({
            roleName,
            companyId: isCompanyScopedRole(roleName) ? companyId : null,
            countryId: roleName === "admin_pays" ? countryId : null,
          }),
        ),
      );

      const initialKeys = new Map(
        initialAssignments
          .filter((a) => a.roleName !== "traveler")
          .map((a) => [roleAssignmentKey(a), a]),
      );

      for (const roleName of selectedRoles) {
        if (!initialKeys.has(roleAssignmentKey({
          roleName,
          companyId: isCompanyScopedRole(roleName) ? companyId : null,
          countryId: roleName === "admin_pays" ? countryId : null,
        }))) {
          await adminAssignUserRoleSupabase({
            userId,
            roleName,
            companyId: isCompanyScopedRole(roleName) ? companyId : null,
            countryId: roleName === "admin_pays" ? countryId : null,
          });
        }
      }

      for (const [key, assignment] of initialKeys) {
        if (!desired.has(key) && ASSIGNABLE_ROLES.includes(assignment.roleName as (typeof ASSIGNABLE_ROLES)[number])) {
          await adminRemoveUserRoleSupabase({
            userId,
            roleName: assignment.roleName,
            companyId: assignment.companyId,
            countryId: assignment.countryId,
          });
        }
      }

      toast.success(t("users.updated"));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.users",
        action: "update",
        summary: `Utilisateur mis à jour : ${email.trim() || userId}`,
        metadata: { userId, roles: selectedRoles },
      });
      navigate(`${base}/admin?tab=users`, { replace: true });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("users.save_error"));
    } finally {
      setSaving(false);
    }
  };

  if (!appUser.isReady) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-8 space-y-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-64 w-full" />
      </div>
    );
  }

  return (
    <AdminAccessGate requireSuperAdmin>
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="icon" asChild>
          <Link to={`${base}/admin?tab=users`}>
            <ArrowLeftIcon className="h-4 w-4" />
          </Link>
        </Button>
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            {t("users.admin_section")}
          </p>
          <h1 className="text-2xl font-extrabold tracking-tight text-[#1A5296]">
            {isEdit ? t("users.edit_title") : t("users.create_title")}
          </h1>
        </div>
      </div>

      {!isEdit && (
        <Card className="border-sky-200 bg-sky-50/80">
          <CardContent className="p-4 flex gap-3 text-sm text-sky-900">
            <ShieldIcon className="h-5 w-5 shrink-0 mt-0.5" />
            <p>{t("users.create_banner")}</p>
          </CardContent>
        </Card>
      )}

      {loading ? (
        <div className="space-y-3">
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-32 w-full" />
        </div>
      ) : (
        <div className="space-y-5">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="firstName">{t("users.first_name")}</Label>
              <Input
                id="firstName"
                value={firstName}
                onChange={(e) => setFirstName(e.target.value)}
                disabled={isEdit}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="lastName">{t("users.last_name")}</Label>
              <Input
                id="lastName"
                value={lastName}
                onChange={(e) => setLastName(e.target.value)}
                disabled={isEdit}
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="email">{t("users.email")}</Label>
            <Input
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              disabled={isEdit}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="phone">{t("users.phone")}</Label>
            <Input
              id="phone"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              disabled={isEdit}
            />
          </div>

          {!isEdit && (
            <div className="space-y-2">
              <Label htmlFor="password">{t("users.temp_password")}</Label>
              <Input
                id="password"
                type="text"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
              <p className="text-xs text-muted-foreground">{t("users.password_hint")}</p>
            </div>
          )}

          <div className="space-y-3">
            <Label>{t("users.roles_label")}</Label>
            <p className="text-xs text-muted-foreground">{t("users.roles_multi_hint")}</p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
              {roles.map((role) => {
                const uiRole = role.name === "super_admin" ? "superadmin" : role.name;
                return (
                  <label
                    key={role.id}
                    className="flex items-start gap-2 rounded-lg border p-3 cursor-pointer hover:bg-muted/50"
                  >
                    <Checkbox
                      checked={selectedRoles.includes(role.name)}
                      onCheckedChange={(checked) => toggleRole(role.name, Boolean(checked))}
                    />
                    <span className="text-sm">
                      <span className="font-medium block">
                        {tc(`roles.${uiRole}`, { defaultValue: role.name })}
                      </span>
                      {role.description ? (
                        <span className="text-xs text-muted-foreground">{role.description}</span>
                      ) : null}
                    </span>
                  </label>
                );
              })}
            </div>
          </div>

          {needsCompany && (
            <div className="space-y-2">
              <Label>{t("users.company")}</Label>
              <Select value={companyId} onValueChange={setCompanyId}>
                <SelectTrigger>
                  <SelectValue placeholder={t("users.select_company")} />
                </SelectTrigger>
                <SelectContent>
                  {companies.map((c) => (
                    <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}

          {needsCountry && (
            <div className="space-y-2">
              <Label>{t("users.country")}</Label>
              <Select value={countryId} onValueChange={setCountryId}>
                <SelectTrigger>
                  <SelectValue placeholder={t("users.select_country")} />
                </SelectTrigger>
                <SelectContent>
                  {countries.map((c) => (
                    <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}

          <div className="flex justify-end gap-2 pt-2">
            <Button variant="secondary" asChild>
              <Link to={`${base}/admin?tab=users`}>{tc("buttons.cancel")}</Link>
            </Button>
            <Button
              onClick={isEdit ? handleEdit : handleCreate}
              disabled={saving}
            >
              <UserPlusIcon className="h-4 w-4 mr-1.5" />
              {saving
                ? tc("buttons.saving", { defaultValue: "Enregistrement..." })
                : isEdit
                  ? tc("buttons.save", { defaultValue: "Enregistrer" })
                  : t("users.create_btn")}
            </Button>
          </div>
        </div>
      )}

      <AdminAuditHub moduleKey="admin.users" scopeLabel="users" />
    </div>
    </AdminAccessGate>
  );
}
