import { useState } from "react";
import { useQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { useNavigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import {
  ShieldIcon,
  UsersIcon,
  BuildingIcon,
  SearchIcon,
  ChevronDownIcon,
  CreditCardIcon,
  PlusIcon,
  SettingsIcon,
  PowerIcon,
  GlobeIcon,
  MapPinIcon,
  Trash2Icon,
  KeyIcon,
  CheckIcon,
  PercentIcon,
  CircleDollarSignIcon,
  MessageCircleIcon,
  PencilIcon,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar.tsx";
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
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import { toast } from "sonner";
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription, EmptyContent } from "@/components/ui/empty.tsx";
import { cn } from "@/lib/utils.ts";
import LandingCmsTab from "./_components/LandingCmsTab.tsx";

const ROLE_COLORS: Record<string, string> = {
  superadmin: "bg-primary/15 text-primary border-primary/30",
  owner: "bg-orange-100 text-orange-700 border-orange-200 dark:bg-orange-900/30 dark:text-orange-400",
  seller: "bg-emerald-100 text-emerald-700 border-emerald-200 dark:bg-emerald-900/30 dark:text-emerald-400",
  traveler: "bg-muted text-muted-foreground border-border",
};

type UserDoc = {
  _id: Id<"users">;
  name?: string;
  email?: string;
  avatar?: string;
  role?: string;
  companyId?: Id<"companies">;
};

type CompanyDoc = {
  _id: Id<"companies">;
  ownerId: Id<"users">;
  name: string;
  description?: string;
  phone?: string;
  email?: string;
  website?: string;
  isActive: boolean;
  planId?: string;
  subscriptionStatus?: string;
  planExpiresAt?: string;
};

type TabId = "users" | "companies" | "subscriptions" | "plans" | "commissions" | "geography" | "roles" | "contact" | "landing";

function RoleBadge({ role }: { role?: string }) {
  const { t } = useTranslation("common");
  const r = role ?? "traveler";
  return (
    <span className={cn("text-[11px] font-semibold px-2 py-0.5 rounded-full border", ROLE_COLORS[r])}>
      {t(`roles.${r}`, { defaultValue: r })}
    </span>
  );
}

// ─── Edit Role Dialog ──────────────────────────────────────────────────────────

function EditRoleDialog({ user, onClose }: { user: UserDoc; onClose: () => void }) {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const [role, setRole] = useState(user.role ?? "traveler");
  const [loading, setLoading] = useState(false);
  const setUserRole = useMutation(api.users.setUserRole);

  const handleSave = async () => {
    setLoading(true);
    try {
      await setUserRole({ userId: user._id, role });
      toast.success(t("role_updated", { role: tc(`roles.${role}`, { defaultValue: role }) }));
      onClose();
    } catch {
      toast.error(t("failed_update_role"));
    } finally {
      setLoading(false);
    }
  };

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>{t("edit_role")}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="flex items-center gap-3 p-3 rounded-xl bg-muted">
            <Avatar className="h-10 w-10">
              <AvatarImage src={user.avatar} />
              <AvatarFallback className="bg-primary/20 text-primary font-bold text-sm">
                {user.name?.charAt(0) ?? "U"}
              </AvatarFallback>
            </Avatar>
            <div>
              <div className="font-semibold text-sm">{user.name ?? "Unknown"}</div>
              <div className="text-xs text-muted-foreground">{user.email ?? "No email"}</div>
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>{t("assign_role")}</Label>
            <Select value={role} onValueChange={setRole}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="traveler">{tc("roles.traveler")}</SelectItem>
                <SelectItem value="owner">{tc("roles.owner")}</SelectItem>
                <SelectItem value="seller">{tc("roles.seller")}</SelectItem>
                <SelectItem value="superadmin">{tc("roles.superadmin")}</SelectItem>
              </SelectContent>
            </Select>
          </div>
          {role === "superadmin" && (
            <p className="text-xs text-destructive bg-destructive/10 p-2 rounded-lg">
              {t("superadmin_warning")}
            </p>
          )}
        </div>
        <DialogFooter>
          <Button variant="secondary" onClick={onClose} disabled={loading} className="cursor-pointer">
            {tc("buttons.cancel")}
          </Button>
          <Button onClick={handleSave} disabled={loading} className="cursor-pointer">
            {loading ? tc("buttons.saving") : t("save_role")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ─── Create Company Dialog ─────────────────────────────────────────────────────

function CreateCompanyDialog({ onClose }: { onClose: () => void }) {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [website, setWebsite] = useState("");
  const [ownerId, setOwnerId] = useState("");
  const [loading, setLoading] = useState(false);
  const create = useMutation(api.companies.adminCreateCompany);
  const users = useQuery(api.users.listUsersForOwnerPicker, {});

  const handleCreate = async () => {
    if (!name.trim() || !ownerId) return;
    setLoading(true);
    try {
      await create({
        ownerId: ownerId as Id<"users">,
        name: name.trim(),
        description: description.trim() || undefined,
        phone: phone.trim() || undefined,
        email: email.trim() || undefined,
        website: website.trim() || undefined,
      });
      toast.success(t("company_created"));
      onClose();
    } catch (err) {
      const msg = err instanceof Error ? err.message : t("company_create_error");
      toast.error(msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-md max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{t("create_company_title")}</DialogTitle>
          <DialogDescription>{t("create_company_desc")}</DialogDescription>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="space-y-1.5">
            <Label>{t("assign_owner")} *</Label>
            <Select value={ownerId} onValueChange={setOwnerId}>
              <SelectTrigger>
                <SelectValue placeholder={t("select_owner")} />
              </SelectTrigger>
              <SelectContent>
                {users?.map((u) => (
                  <SelectItem key={u._id} value={u._id}>
                    {u.name ?? u.email ?? "Unknown"} — {u.email ?? ""}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>{t("company_name")} *</Label>
            <Input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t("company_name_placeholder")}
            />
          </div>
          <div className="space-y-1.5">
            <Label>{t("company_desc")}</Label>
            <Textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder={t("company_desc_placeholder")}
              rows={3}
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>{t("company_phone")}</Label>
              <Input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="+237..." />
            </div>
            <div className="space-y-1.5">
              <Label>{t("company_email")}</Label>
              <Input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="contact@company.com" />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>{t("company_website")}</Label>
            <Input value={website} onChange={(e) => setWebsite(e.target.value)} placeholder="https://..." />
          </div>
        </div>
        <DialogFooter>
          <Button variant="secondary" onClick={onClose} disabled={loading} className="cursor-pointer">
            {tc("buttons.cancel")}
          </Button>
          <Button onClick={handleCreate} disabled={loading || !name.trim() || !ownerId} className="cursor-pointer">
            {loading ? tc("buttons.saving") : tc("buttons.save")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ─── Manage Subscription Dialog ────────────────────────────────────────────────

function ManageSubDialog({
  company,
  onClose,
}: {
  company: CompanyDoc;
  onClose: () => void;
}) {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const [planId, setPlanId] = useState(company.planId ?? "none");
  const [status, setStatus] = useState(company.subscriptionStatus ?? "none");
  const [loading, setLoading] = useState(false);
  const setSub = useMutation(api.companies.adminSetSubscription);

  const handleSave = async () => {
    setLoading(true);
    try {
      await setSub({
        companyId: company._id,
        planId,
        subscriptionStatus: status,
      });
      toast.success(t("sub_updated"));
      onClose();
    } catch {
      toast.error(t("sub_update_error"));
    } finally {
      setLoading(false);
    }
  };

  return (
    <Dialog open onOpenChange={onClose}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>{t("manage_sub_title")}</DialogTitle>
          <DialogDescription>{company.name} — {t("manage_sub_desc")}</DialogDescription>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="space-y-1.5">
            <Label>{t("select_plan")}</Label>
            <Select value={planId} onValueChange={setPlanId}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="none">{t("plan_none")}</SelectItem>
                <SelectItem value="basic">{t("plan_basic")}</SelectItem>
                <SelectItem value="pro">{t("plan_pro")}</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>{t("select_status")}</Label>
            <Select value={status} onValueChange={setStatus}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="none">{t("status_none")}</SelectItem>
                <SelectItem value="active">{t("status_active")}</SelectItem>
                <SelectItem value="past_due">{t("status_past_due")}</SelectItem>
                <SelectItem value="cancelled">{t("status_cancelled")}</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <DialogFooter>
          <Button variant="secondary" onClick={onClose} disabled={loading} className="cursor-pointer">
            {tc("buttons.cancel")}
          </Button>
          <Button onClick={handleSave} disabled={loading} className="cursor-pointer">
            {loading ? tc("buttons.saving") : tc("buttons.save")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ─── User Row ──────────────────────────────────────────────────────────────────

function UserRow({ user, onEdit }: { user: UserDoc; onEdit: (u: UserDoc) => void }) {
  const { t } = useTranslation("common");
  return (
    <div className="flex items-center gap-3 p-3 rounded-xl hover:bg-muted/50 transition-colors">
      <Avatar className="h-9 w-9 shrink-0">
        <AvatarImage src={user.avatar} />
        <AvatarFallback className="bg-primary/15 text-primary font-bold text-xs">
          {user.name?.charAt(0) ?? "U"}
        </AvatarFallback>
      </Avatar>
      <div className="flex-1 min-w-0">
        <div className="font-medium text-sm truncate">{user.name ?? "No name"}</div>
        <div className="text-xs text-muted-foreground truncate">{user.email ?? "No email"}</div>
      </div>
      <RoleBadge role={user.role} />
      <Button
        size="sm"
        variant="ghost"
        className="shrink-0 h-7 text-xs cursor-pointer"
        onClick={() => onEdit(user)}
      >
        {t("buttons.edit")}
      </Button>
    </div>
  );
}

// ─── Company Row ───────────────────────────────────────────────────────────────

function CompanyRow({
  company,
  ownerName,
  onManageSub,
  onToggle,
  onManageResources,
}: {
  company: CompanyDoc;
  ownerName: string;
  onManageSub: (c: CompanyDoc) => void;
  onToggle: (c: CompanyDoc) => void;
  onManageResources: (c: CompanyDoc) => void;
}) {
  const { t } = useTranslation("admin");
  const status = company.subscriptionStatus ?? "none";
  const statusCls: Record<string, string> = {
    active: "bg-green-500/10 text-green-600 border-green-500/30",
    past_due: "bg-yellow-500/10 text-yellow-600 border-yellow-500/30",
    cancelled: "bg-red-500/10 text-red-600 border-red-500/30",
    none: "bg-muted text-muted-foreground border-border",
  };

  return (
    <div className="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-3 p-3 rounded-xl hover:bg-muted/50 transition-colors">
      <div className="flex items-center gap-3 flex-1 min-w-0">
        <div className="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
          <BuildingIcon className="w-4 h-4 text-primary" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="font-medium text-sm truncate">{company.name}</div>
          <div className="text-xs text-muted-foreground truncate">
            {t("owner_label")}: {ownerName} {company.isActive ? "" : `(${t("deactivate_company")})`}
          </div>
        </div>
        {company.planId && status === "active" && (
          <Badge className="text-[10px] shrink-0">{company.planId.toUpperCase()}</Badge>
        )}
        <span
          className={cn(
            "text-[11px] font-semibold px-2 py-0.5 rounded-full border shrink-0",
            statusCls[status] ?? statusCls.none,
          )}
        >
          {t(`status_${status}`, { defaultValue: status })}
        </span>
      </div>
      <div className="flex items-center gap-1 shrink-0 pl-12 sm:pl-0">
        <Button
          size="sm"
          className="h-7 text-xs cursor-pointer"
          onClick={() => onManageResources(company)}
        >
          {t("manage_resources", { defaultValue: "Manage" })}
        </Button>
        <Button
          size="sm"
          variant="ghost"
          className="h-7 text-xs cursor-pointer"
          onClick={() => onManageSub(company)}
        >
          <SettingsIcon className="w-3 h-3 mr-1" />
          {t("manage_sub")}
        </Button>
        <Button
          size="sm"
          variant="ghost"
          className="h-7 text-xs cursor-pointer"
          onClick={() => onToggle(company)}
        >
          <PowerIcon className="w-3 h-3 mr-1" />
          {company.isActive ? t("deactivate_company") : t("activate_company")}
        </Button>
      </div>
    </div>
  );
}

// ─── Main Admin Panel ──────────────────────────────────────────────────────────

export default function AdminPanel() {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const { lng } = useParams<{ lng: string }>();
  const currentUser = useQuery(api.users.getCurrentUser, {});
  const navigate = useNavigate();

  const [tab, setTab] = useState<TabId>("users");
  const [roleFilter, setRoleFilter] = useState("all");
  const [search, setSearch] = useState("");
  const [editUser, setEditUser] = useState<UserDoc | null>(null);
  const [showCreateCompany, setShowCreateCompany] = useState(false);
  const [manageSub, setManageSub] = useState<CompanyDoc | null>(null);

  const usersResult = useQuery(api.users.listAllUsers, {
    paginationOpts: { numItems: 50, cursor: null },
    roleFilter: roleFilter === "all" ? undefined : roleFilter,
  });

  const allCompanies = useQuery(api.companies.listAllCompanies, {});
  const allUsersForPicker = useQuery(api.users.listUsersForOwnerPicker, {});
  const toggleActive = useMutation(api.companies.toggleCompanyActive);

  // Redirect non-superadmins
  if (currentUser === undefined) {
    return (
      <div className="max-w-4xl mx-auto px-4 py-8 space-y-6">
        <div className="flex items-center gap-3">
          <Skeleton className="w-10 h-10 rounded-xl" />
          <div className="space-y-2">
            <Skeleton className="h-6 w-48" />
            <Skeleton className="h-4 w-32" />
          </div>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          {Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-24 rounded-xl" />)}
        </div>
        <Skeleton className="h-12 w-full rounded-xl" />
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    );
  }
  if (currentUser?.role !== "superadmin") {
    navigate(`/${lng}`, { replace: true });
    return null;
  }

  const users = usersResult?.page ?? [];
  const filtered = search.trim()
    ? users.filter(
        (u) =>
          u.name?.toLowerCase().includes(search.toLowerCase()) ||
          u.email?.toLowerCase().includes(search.toLowerCase()),
      )
    : users;

  const roleCounts = {
    all: usersResult?.page.length ?? 0,
    superadmin: users.filter((u) => u.role === "superadmin").length,
    owner: users.filter((u) => u.role === "owner").length,
    seller: users.filter((u) => u.role === "seller").length,
    traveler: users.filter((u) => !u.role || u.role === "traveler").length,
  };

  const companies = allCompanies ?? [];
  const activeSubs = companies.filter((c) => c.subscriptionStatus === "active").length;

  // Map ownerId -> name for display
  const ownerNameMap = new Map<string, string>();
  for (const u of allUsersForPicker ?? []) {
    ownerNameMap.set(u._id, u.name ?? u.email ?? "Unknown");
  }

  const handleToggleCompany = async (company: CompanyDoc) => {
    try {
      await toggleActive({ companyId: company._id, isActive: !company.isActive });
      toast.success(t("company_toggled"));
    } catch {
      toast.error(t("company_toggle_error"));
    }
  };

  const tabs: { id: TabId; label: string; icon: typeof UsersIcon }[] = [
    { id: "users", label: t("tabs.users"), icon: UsersIcon },
    { id: "companies", label: t("tabs.companies"), icon: BuildingIcon },
    { id: "subscriptions", label: t("tabs.subscriptions"), icon: CreditCardIcon },
    { id: "plans", label: t("tabs.plans"), icon: SettingsIcon },
    { id: "commissions", label: t("tabs.commissions"), icon: PercentIcon },
    { id: "geography", label: t("tabs.geography"), icon: GlobeIcon },
    { id: "roles", label: t("tabs.roles"), icon: KeyIcon },
    { id: "contact", label: t("tabs.contact", { defaultValue: "Contact" }), icon: MessageCircleIcon },
    { id: "landing", label: t("tabs.landing", { defaultValue: "Landing Page" }), icon: PencilIcon },
  ];

  const stats = [
    { labelKey: "total_users", count: roleCounts.all, icon: UsersIcon, color: "text-primary" },
    { labelKey: "total_companies", count: companies.length, icon: BuildingIcon, color: "text-orange-500" },
    { labelKey: "active_subs", count: activeSubs, icon: CreditCardIcon, color: "text-emerald-500" },
    { labelKey: "travelers", count: roleCounts.traveler, icon: UsersIcon, color: "text-muted-foreground" },
  ] as const;

  return (
    <div className="max-w-4xl mx-auto px-4 py-8 space-y-6">
      {/* Header */}
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl bg-primary flex items-center justify-center">
          <ShieldIcon className="w-5 h-5 text-primary-foreground" />
        </div>
        <div>
          <h1 className="text-2xl font-extrabold tracking-tight">{t("title")}</h1>
          <p className="text-sm text-muted-foreground">{t("desc")}</p>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {stats.map(({ labelKey, count, icon: Icon, color }) => (
          <Card key={labelKey} className="p-4">
            <div className="w-8 h-8 rounded-lg bg-muted flex items-center justify-center mb-2">
              <Icon className={cn("w-4 h-4", color)} />
            </div>
            <div className="text-2xl font-bold">{count}</div>
            <div className="text-xs text-muted-foreground">{t(labelKey)}</div>
          </Card>
        ))}
      </div>

      {/* Tabs */}
      <div className="flex gap-1 bg-muted p-1 rounded-xl">
        {tabs.map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            onClick={() => setTab(id)}
            className={cn(
              "flex-1 flex items-center justify-center gap-2 py-2 px-3 rounded-lg text-sm font-medium transition-colors cursor-pointer",
              tab === id
                ? "bg-background shadow-sm text-foreground"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            <Icon className="w-4 h-4" />
            <span className="hidden sm:inline">{label}</span>
          </button>
        ))}
      </div>

      {/* Tab Content: Users */}
      {tab === "users" && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base">{t("users")}</CardTitle>
            <div className="flex flex-col sm:flex-row gap-2 mt-2">
              <div className="relative flex-1">
                <SearchIcon className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <Input
                  placeholder={t("search_users")}
                  className="pl-9"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                />
              </div>
              <Select value={roleFilter} onValueChange={setRoleFilter}>
                <SelectTrigger className="w-full sm:w-40">
                  <SelectValue placeholder={t("filter_role")} />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">{t("all_roles")}</SelectItem>
                  <SelectItem value="superadmin">{tc("roles.superadmin")}</SelectItem>
                  <SelectItem value="owner">{tc("roles.owner")}</SelectItem>
                  <SelectItem value="seller">{tc("roles.seller")}</SelectItem>
                  <SelectItem value="traveler">{tc("roles.traveler")}</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </CardHeader>
          <CardContent className="p-2">
            {usersResult === undefined ? (
              <div className="space-y-2 p-2">
                {Array.from({ length: 5 }).map((_, i) => (
                  <Skeleton key={i} className="h-14 w-full rounded-xl" />
                ))}
              </div>
            ) : filtered.length === 0 ? (
              <div className="p-4">
                <Empty>
                  <EmptyHeader>
                    <EmptyMedia variant="icon"><UsersIcon /></EmptyMedia>
                    <EmptyTitle>{t("no_users")}</EmptyTitle>
                    <EmptyDescription>{t("no_users_desc", { defaultValue: "No users match your current filters." })}</EmptyDescription>
                  </EmptyHeader>
                </Empty>
              </div>
            ) : (
              <div className="space-y-0.5">
                {filtered.map((u) => (
                  <UserRow key={u._id} user={u as UserDoc} onEdit={setEditUser} />
                ))}
              </div>
            )}
            {usersResult && !usersResult.isDone && (
              <div className="pt-2 px-2">
                <Button variant="secondary" size="sm" className="w-full text-xs cursor-pointer">
                  <ChevronDownIcon className="w-3 h-3 mr-1" /> {tc("buttons.load_more")}
                </Button>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Tab Content: Companies */}
      {tab === "companies" && (
        <Card>
          <CardHeader className="pb-3">
            <div className="flex items-center justify-between">
              <CardTitle className="text-base flex items-center gap-2">
                <BuildingIcon className="w-4 h-4" /> {t("tabs.companies")}
              </CardTitle>
              <Button
                size="sm"
                className="cursor-pointer"
                onClick={() => setShowCreateCompany(true)}
              >
                <PlusIcon className="w-4 h-4 mr-1" /> {t("create_company")}
              </Button>
            </div>
          </CardHeader>
          <CardContent className="p-2">
            {allCompanies === undefined ? (
              <div className="space-y-2 p-2">
                {Array.from({ length: 3 }).map((_, i) => (
                  <Skeleton key={i} className="h-14 w-full rounded-xl" />
                ))}
              </div>
            ) : companies.length === 0 ? (
              <div className="p-4">
                <Empty>
                  <EmptyHeader>
                    <EmptyMedia variant="icon"><BuildingIcon /></EmptyMedia>
                    <EmptyTitle>{t("no_companies")}</EmptyTitle>
                    <EmptyDescription>{t("no_companies_desc", { defaultValue: "No companies have been created yet." })}</EmptyDescription>
                  </EmptyHeader>
                  <EmptyContent>
                    <Button size="sm" onClick={() => setShowCreateCompany(true)}>
                      <PlusIcon className="w-4 h-4 mr-1" /> {t("create_company")}
                    </Button>
                  </EmptyContent>
                </Empty>
              </div>
            ) : (
              <div className="space-y-0.5">
                {companies.map((c) => (
                  <CompanyRow
                    key={c._id}
                    company={c as CompanyDoc}
                    ownerName={ownerNameMap.get(c.ownerId) ?? "Unknown"}
                    onManageSub={setManageSub}
                    onToggle={handleToggleCompany}
                    onManageResources={(co) => navigate(`/${lng}/admin/company/${co._id}`)}
                  />
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Tab Content: Subscriptions */}
      {tab === "subscriptions" && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base flex items-center gap-2">
              <CreditCardIcon className="w-4 h-4" /> {t("company_subs")}
            </CardTitle>
          </CardHeader>
          <CardContent className="p-2">
            {allCompanies === undefined ? (
              <div className="space-y-2 p-2">
                {Array.from({ length: 3 }).map((_, i) => (
                  <Skeleton key={i} className="h-14 w-full rounded-xl" />
                ))}
              </div>
            ) : companies.length === 0 ? (
              <div className="p-4">
                <Empty>
                  <EmptyHeader>
                    <EmptyMedia variant="icon"><CreditCardIcon /></EmptyMedia>
                    <EmptyTitle>{t("no_companies")}</EmptyTitle>
                    <EmptyDescription>{t("no_subs_desc", { defaultValue: "No subscriptions to manage yet." })}</EmptyDescription>
                  </EmptyHeader>
                </Empty>
              </div>
            ) : (
              <div className="space-y-0.5">
                {companies.map((c) => {
                  const status = c.subscriptionStatus ?? "none";
                  const statusCls: Record<string, string> = {
                    active: "bg-green-500/10 text-green-600 border-green-500/30",
                    past_due: "bg-yellow-500/10 text-yellow-600 border-yellow-500/30",
                    cancelled: "bg-red-500/10 text-red-600 border-red-500/30",
                    none: "bg-muted text-muted-foreground border-border",
                  };
                  return (
                    <div
                      key={c._id}
                      className="flex items-center gap-3 p-3 rounded-xl hover:bg-muted/50 transition-colors"
                    >
                      <div className="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
                        <BuildingIcon className="w-4 h-4 text-primary" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="font-medium text-sm truncate">{c.name}</div>
                        <div className="text-xs text-muted-foreground truncate">
                          {c.planId ? `${c.planId.toUpperCase()} Plan` : tc("labels.no_plan")}
                          {c.planExpiresAt
                            ? ` — ${new Date(c.planExpiresAt).toLocaleDateString()}`
                            : ""}
                        </div>
                      </div>
                      <span
                        className={cn(
                          "text-[11px] font-semibold px-2 py-0.5 rounded-full border shrink-0",
                          statusCls[status] ?? statusCls.none,
                        )}
                      >
                        {t(`status_${status}`, { defaultValue: status })}
                      </span>
                      <Button
                        size="sm"
                        variant="ghost"
                        className="shrink-0 h-7 text-xs cursor-pointer"
                        onClick={() => setManageSub(c as CompanyDoc)}
                      >
                        <SettingsIcon className="w-3 h-3 mr-1" />
                        {t("manage_sub")}
                      </Button>
                    </div>
                  );
                })}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Tab Content: Geography */}
      {tab === "geography" && <GeographyTab />}

      {/* Tab Content: Plans */}
      {tab === "plans" && <PlansTab />}

      {/* Tab Content: Commissions */}
      {tab === "commissions" && <CommissionsTab />}

      {/* Tab Content: Roles & Permissions */}
      {tab === "roles" && <RolesTab />}

      {/* Tab Content: Contact / WhatsApp */}
      {tab === "contact" && <ContactSettingsTab />}

      {/* Tab Content: Landing Page CMS */}
      {tab === "landing" && <LandingCmsTab />}

      {/* Dialogs */}
      {editUser && <EditRoleDialog user={editUser} onClose={() => setEditUser(null)} />}
      {showCreateCompany && <CreateCompanyDialog onClose={() => setShowCreateCompany(false)} />}
      {manageSub && <ManageSubDialog company={manageSub} onClose={() => setManageSub(null)} />}
    </div>
  );
}

// ─── Plans Tab ──────────────────────────────────────────────────────────────

function PlansTab() {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const plans = useQuery(api.subscriptionPlans.listAll, {});
  const createPlan = useMutation(api.subscriptionPlans.create);
  const updatePlan = useMutation(api.subscriptionPlans.update);
  const removePlan = useMutation(api.subscriptionPlans.remove);

  const [showAdd, setShowAdd] = useState(false);
  const [name, setName] = useState("");
  const [durationDays, setDurationDays] = useState("30");
  const [price, setPrice] = useState("0");
  const [currency, setCurrency] = useState("XAF");
  const [isDefault, setIsDefault] = useState(false);
  const [loading, setLoading] = useState(false);

  const handleCreate = async () => {
    if (!name.trim()) return;
    setLoading(true);
    try {
      await createPlan({
        name: name.trim(),
        durationDays: Number(durationDays),
        price: Number(price),
        currency,
        isDefault,
      });
      toast.success(t("plans.created"));
      setShowAdd(false);
      setName("");
      setDurationDays("30");
      setPrice("0");
      setIsDefault(false);
    } catch {
      toast.error(t("plans.create_error"));
    } finally {
      setLoading(false);
    }
  };

  const handleToggleActive = async (planId: Id<"subscriptionPlans">, currentActive: boolean) => {
    try {
      await updatePlan({ planId, isActive: !currentActive });
      toast.success(t("plans.updated"));
    } catch {
      toast.error(t("plans.update_error"));
    }
  };

  const handleSetDefault = async (planId: Id<"subscriptionPlans">) => {
    try {
      await updatePlan({ planId, isDefault: true });
      toast.success(t("plans.set_default"));
    } catch {
      toast.error(t("plans.update_error"));
    }
  };

  const handleDelete = async (planId: Id<"subscriptionPlans">) => {
    try {
      await removePlan({ planId });
      toast.success(t("plans.deleted"));
    } catch {
      toast.error(t("plans.delete_error"));
    }
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
          <CardTitle className="text-base">{t("plans.title")}</CardTitle>
          <Button size="sm" onClick={() => setShowAdd(true)} className="cursor-pointer">
            <PlusIcon className="w-4 h-4 mr-1" /> {t("plans.add")}
          </Button>
        </div>
        <p className="text-xs text-muted-foreground mt-1">{t("plans.desc")}</p>
      </CardHeader>
      <CardContent className="space-y-3">
        {!plans || plans.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon"><SettingsIcon /></EmptyMedia>
              <EmptyTitle>{t("plans.no_plans")}</EmptyTitle>
              <EmptyDescription>{t("plans.no_plans_desc", { defaultValue: "Create subscription plans for companies." })}</EmptyDescription>
            </EmptyHeader>
            <EmptyContent>
              <Button size="sm" onClick={() => setShowAdd(true)}>
                <PlusIcon className="w-4 h-4 mr-1" /> {t("plans.add")}
              </Button>
            </EmptyContent>
          </Empty>
        ) : (
          plans.map((plan) => (
            <div
              key={plan._id}
              className={cn(
                "rounded-lg border p-4 flex items-center justify-between gap-3",
                !plan.isActive && "opacity-50",
              )}
            >
              <div className="space-y-1">
                <div className="flex items-center gap-2">
                  <span className="font-semibold text-sm">{plan.name}</span>
                  {plan.isDefault && (
                    <Badge className="text-[9px] bg-blue-500/10 text-blue-600 border-blue-500/30">
                      {t("plans.default_trial")}
                    </Badge>
                  )}
                  {!plan.isActive && (
                    <Badge variant="secondary" className="text-[9px]">
                      {t("plans.inactive")}
                    </Badge>
                  )}
                </div>
                <p className="text-xs text-muted-foreground">
                  {plan.price === 0 ? t("plans.free") : `${plan.currency} ${plan.price.toLocaleString()}`}
                  {" "}&middot;{" "}
                  {plan.durationDays} {t("plans.days")}
                </p>
              </div>
              <div className="flex items-center gap-1">
                {!plan.isDefault && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => handleSetDefault(plan._id)}
                    className="text-xs cursor-pointer"
                    title={t("plans.make_default")}
                  >
                    {t("plans.make_default")}
                  </Button>
                )}
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => handleToggleActive(plan._id, plan.isActive)}
                  className="text-xs cursor-pointer"
                >
                  {plan.isActive ? t("plans.deactivate") : t("plans.activate")}
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => handleDelete(plan._id)}
                  className="text-xs text-destructive cursor-pointer"
                >
                  <Trash2Icon className="w-3.5 h-3.5" />
                </Button>
              </div>
            </div>
          ))
        )}
      </CardContent>

      {/* Add Plan Dialog */}
      <Dialog open={showAdd} onOpenChange={setShowAdd}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>{t("plans.add_title")}</DialogTitle>
            <DialogDescription>{t("plans.add_desc")}</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-1.5">
              <Label>{t("plans.name_label")} *</Label>
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Monthly, Quarterly" />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>{t("plans.duration_label")} *</Label>
                <Input type="number" value={durationDays} onChange={(e) => setDurationDays(e.target.value)} min={1} />
              </div>
              <div className="space-y-1.5">
                <Label>{t("plans.price_label")} *</Label>
                <Input type="number" value={price} onChange={(e) => setPrice(e.target.value)} min={0} />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label>{t("plans.currency_label")}</Label>
              <Input value={currency} onChange={(e) => setCurrency(e.target.value)} placeholder="XAF" />
            </div>
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={isDefault}
                onChange={(e) => setIsDefault(e.target.checked)}
                className="rounded border-border"
              />
              <span className="text-sm">{t("plans.set_as_default")}</span>
            </label>
            <p className="text-[11px] text-muted-foreground">{t("plans.default_hint")}</p>
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setShowAdd(false)} className="cursor-pointer">
              {tc("buttons.cancel")}
            </Button>
            <Button onClick={handleCreate} disabled={loading || !name.trim()} className="cursor-pointer">
              {loading ? tc("buttons.saving") : t("plans.add")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}

// ─── Commissions Tab ─────────────────────────────────────────────────────────

function CommissionsTab() {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const allCompanies = useQuery(api.companies.listAllCompanies, {});
  const summary = useQuery(api.commissions.getCommissionSummary, {});
  const allEntries = useQuery(api.commissions.listAllCommissions, {});
  const setCommission = useMutation(api.commissions.setCompanyCommission);
  const markPaid = useMutation(api.commissions.markCommissionsPaid);

  const [showSetDialog, setShowSetDialog] = useState(false);
  const [selectedCompanyId, setSelectedCompanyId] = useState("");
  const [rate, setRate] = useState("10");
  const [paidBy, setPaidBy] = useState("company");
  const [loading, setLoading] = useState(false);
  const [viewTab, setViewTab] = useState<"summary" | "pending" | "paid">("summary");

  const handleSetCommission = async () => {
    if (!selectedCompanyId) return;
    setLoading(true);
    try {
      await setCommission({
        companyId: selectedCompanyId as Id<"companies">,
        rate: Number(rate) || 0,
        paidBy,
      });
      toast.success(t("commissions.updated"));
      setShowSetDialog(false);
    } catch {
      toast.error(t("commissions.update_error"));
    } finally {
      setLoading(false);
    }
  };

  const handleMarkPaid = async (companyId: string) => {
    try {
      const result = await markPaid({ companyId: companyId as Id<"companies"> });
      toast.success(t("commissions.marked_paid", { count: result.markedPaid }));
    } catch {
      toast.error(t("commissions.mark_paid_error"));
    }
  };

  const pendingEntries = (allEntries ?? []).filter((e) => e.status === "pending");
  const paidEntries = (allEntries ?? []).filter((e) => e.status === "paid");

  const subTabs = [
    { id: "summary" as const, label: t("commissions.summary") },
    { id: "pending" as const, label: `${t("commissions.pending")} (${pendingEntries.length})` },
    { id: "paid" as const, label: `${t("commissions.paid")} (${paidEntries.length})` },
  ];

  return (
    <div className="space-y-4">
      {/* Header with Set Commission button */}
      <Card>
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between">
            <CardTitle className="text-base flex items-center gap-2">
              <PercentIcon className="w-4 h-4" /> {t("commissions.title")}
            </CardTitle>
            <Button size="sm" className="cursor-pointer" onClick={() => setShowSetDialog(true)}>
              <SettingsIcon className="w-4 h-4 mr-1" /> {t("commissions.set")}
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          {/* Sub-tabs */}
          <div className="flex gap-1 bg-muted p-1 rounded-lg mb-4">
            {subTabs.map((st) => (
              <button
                key={st.id}
                onClick={() => setViewTab(st.id)}
                className={cn(
                  "flex-1 py-1.5 px-3 rounded-md text-xs font-medium transition-colors cursor-pointer",
                  viewTab === st.id
                    ? "bg-background shadow-sm text-foreground"
                    : "text-muted-foreground hover:text-foreground"
                )}
              >
                {st.label}
              </button>
            ))}
          </div>

          {/* Summary view */}
          {viewTab === "summary" && (
            <>
              {summary === undefined ? (
                <div className="space-y-2">
                  {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-14 w-full rounded-xl" />)}
                </div>
              ) : summary.length === 0 ? (
                <Empty>
                  <EmptyHeader>
                    <EmptyMedia variant="icon"><CircleDollarSignIcon /></EmptyMedia>
                    <EmptyTitle>{t("commissions.no_commissions")}</EmptyTitle>
                    <EmptyDescription>{t("commissions.no_commissions_desc", { defaultValue: "Set up commissions for companies to start tracking." })}</EmptyDescription>
                  </EmptyHeader>
                </Empty>
              ) : (
                <div className="space-y-2">
                  {summary.map((s) => (
                    <div key={s.companyId} className="flex items-center gap-3 p-3 rounded-xl border hover:bg-muted/50 transition-colors">
                      <div className="w-9 h-9 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
                        <CircleDollarSignIcon className="w-4 h-4 text-primary" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="font-medium text-sm">{s.companyName}</div>
                        <div className="text-xs text-muted-foreground">
                          Pending: {s.pending.toLocaleString()} {s.currency} | {t("commissions.paid")}: {s.paid.toLocaleString()} {s.currency}
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="text-sm font-bold text-primary">{s.balance.toLocaleString()} {s.currency}</div>
                        <div className="text-[10px] text-muted-foreground">{t("commissions.balance")}</div>
                      </div>
                      {s.pending > 0 && (
                        <Button
                          size="sm"
                          variant="secondary"
                          className="h-7 text-xs cursor-pointer"
                          onClick={() => handleMarkPaid(s.companyId)}
                        >
                          <CheckIcon className="w-3 h-3 mr-1" /> {t("commissions.mark_paid")}
                        </Button>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </>
          )}

          {/* Pending entries */}
          {viewTab === "pending" && (
            <CommissionEntryList entries={pendingEntries} />
          )}

          {/* Paid entries */}
          {viewTab === "paid" && (
            <CommissionEntryList entries={paidEntries} />
          )}
        </CardContent>
      </Card>

      {/* Set Commission Dialog */}
      <Dialog open={showSetDialog} onOpenChange={setShowSetDialog}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>{t("commissions.set_title")}</DialogTitle>
            <DialogDescription>{t("commissions.set_desc")}</DialogDescription>
          </DialogHeader>
          <div className="space-y-3 py-2">
            <div className="space-y-1.5">
              <Label>{t("commissions.company")} *</Label>
              <Select value={selectedCompanyId} onValueChange={setSelectedCompanyId}>
                <SelectTrigger><SelectValue placeholder={t("commissions.select_company")} /></SelectTrigger>
                <SelectContent>
                  {allCompanies?.map((c) => (
                    <SelectItem key={c._id} value={c._id}>{c.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>{t("commissions.rate")}</Label>
              <Input type="number" min={0} max={100} step={0.5} value={rate} onChange={(e) => setRate(e.target.value)} placeholder="10" />
            </div>
            <div className="space-y-1.5">
              <Label>{t("commissions.paid_by")}</Label>
              <Select value={paidBy} onValueChange={setPaidBy}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="company">{t("commissions.paid_by_company")}</SelectItem>
                  <SelectItem value="traveler">{t("commissions.paid_by_traveler")}</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setShowSetDialog(false)} className="cursor-pointer">{tc("buttons.cancel")}</Button>
            <Button onClick={handleSetCommission} disabled={loading || !selectedCompanyId} className="cursor-pointer">
              {loading ? tc("buttons.saving") : tc("buttons.save")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

type CommissionEntry = {
  _id: string;
  companyName: string;
  bookingRef: string;
  passengerName: string;
  amount: number;
  currency: string;
  paidBy: string;
  status: string;
  paidAt?: string;
  _creationTime: number;
};

function CommissionEntryList({ entries }: { entries: CommissionEntry[] }) {
  const { t } = useTranslation("admin");
  if (entries.length === 0) {
    return (
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon"><PercentIcon /></EmptyMedia>
          <EmptyTitle>{t("commissions.no_entries")}</EmptyTitle>
          <EmptyDescription>{t("commissions.no_entries_desc", { defaultValue: "No commission entries in this category." })}</EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }
  return (
    <div className="space-y-1">
      {entries.map((e) => (
        <div key={e._id} className="flex items-center gap-3 p-3 rounded-xl hover:bg-muted/50 transition-colors">
          <CircleDollarSignIcon className="w-4 h-4 text-primary shrink-0" />
          <div className="flex-1 min-w-0">
            <div className="font-medium text-sm">{e.passengerName} — {e.bookingRef}</div>
            <div className="text-xs text-muted-foreground">
              {e.companyName} | {e.paidBy === "company" ? t("commissions.company_pays") : t("commissions.traveler_pays")}
              {e.paidAt ? ` | ${t("commissions.paid_on", { date: new Date(e.paidAt).toLocaleDateString() })}` : ""}
            </div>
          </div>
          <div className="text-sm font-semibold text-primary">
            {e.amount.toLocaleString()} {e.currency}
          </div>
          <Badge variant={e.status === "paid" ? "default" : "secondary"} className="text-[10px]">
            {e.status}
          </Badge>
        </div>
      ))}
    </div>
  );
}

// ─── Geography Tab ────────────────────────────────────────────────────────────

function GeographyTab() {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const countries = useQuery(api.geography.listCountries, {});
  const cities = useQuery(api.geography.listCities, {});
  const createCountry = useMutation(api.geography.createCountry);
  const deleteCountry = useMutation(api.geography.deleteCountry);
  const createCity = useMutation(api.geography.createCity);
  const deleteCity = useMutation(api.geography.deleteCity);

  const [showAddCountry, setShowAddCountry] = useState(false);
  const [countryName, setCountryName] = useState("");
  const [showAddCity, setShowAddCity] = useState(false);
  const [cityName, setCityName] = useState("");
  const [selectedCountryId, setSelectedCountryId] = useState("");
  const [loading, setLoading] = useState(false);

  const handleAddCountry = async () => {
    if (!countryName.trim()) return;
    setLoading(true);
    try {
      await createCountry({ name: countryName.trim() });
      toast.success(t("geo.country_added"));
      setCountryName("");
      setShowAddCountry(false);
    } catch {
      toast.error(t("geo.country_add_error"));
    } finally {
      setLoading(false);
    }
  };

  const handleAddCity = async () => {
    if (!cityName.trim() || !selectedCountryId) return;
    setLoading(true);
    try {
      await createCity({ countryId: selectedCountryId as Id<"countries">, name: cityName.trim() });
      toast.success(t("geo.city_added"));
      setCityName("");
      setSelectedCountryId("");
      setShowAddCity(false);
    } catch {
      toast.error(t("geo.city_add_error"));
    } finally {
      setLoading(false);
    }
  };

  // Group cities by country
  const citiesByCountry = new Map<string, { _id: string; name: string; countryName: string }[]>();
  for (const c of cities ?? []) {
    const key = c.countryId;
    if (!citiesByCountry.has(key)) citiesByCountry.set(key, []);
    citiesByCountry.get(key)!.push(c);
  }

  return (
    <div className="space-y-4">
      {/* Countries Card */}
      <Card>
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between">
            <CardTitle className="text-base flex items-center gap-2">
              <GlobeIcon className="w-4 h-4" /> {t("geo.countries")}
            </CardTitle>
            <Button size="sm" className="cursor-pointer" onClick={() => setShowAddCountry(true)}>
              <PlusIcon className="w-4 h-4 mr-1" /> {t("geo.add_country")}
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          {countries === undefined ? (
            <div className="space-y-2">
              {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-12 w-full rounded-xl" />)}
            </div>
          ) : countries.length === 0 ? (
            <Empty>
              <EmptyHeader>
                <EmptyMedia variant="icon"><GlobeIcon /></EmptyMedia>
                <EmptyTitle>{t("geo.no_countries")}</EmptyTitle>
                <EmptyDescription>{t("geo.no_countries_desc", { defaultValue: "Add your first country to get started." })}</EmptyDescription>
              </EmptyHeader>
              <EmptyContent>
                <Button size="sm" onClick={() => setShowAddCountry(true)}>
                  <PlusIcon className="w-4 h-4 mr-1" /> {t("geo.add_country")}
                </Button>
              </EmptyContent>
            </Empty>
          ) : (
            <div className="space-y-1">
              {countries.map((country) => {
                const countryCities = citiesByCountry.get(country._id) ?? [];
                return (
                  <div key={country._id} className="p-3 rounded-xl hover:bg-muted/50">
                    <div className="flex items-center gap-3">
                      <GlobeIcon className="w-4 h-4 text-primary shrink-0" />
                      <div className="flex-1 min-w-0">
                        <div className="font-medium text-sm">{country.name}</div>
                        <div className="text-xs text-muted-foreground">{t("geo.cities_count", { count: countryCities.length })}</div>
                      </div>
                      <Button
                        variant="ghost"
                        size="sm"
                        className="cursor-pointer h-7 text-xs text-destructive"
                        onClick={() => deleteCountry({ countryId: country._id }).then(() => toast.success(t("geo.country_deleted"))).catch(() => toast.error(t("geo.delete_error")))}
                      >
                        <Trash2Icon className="w-3 h-3" />
                      </Button>
                    </div>
                    {countryCities.length > 0 && (
                      <div className="ml-7 mt-2 space-y-1">
                        {countryCities.map((city) => (
                          <div key={city._id} className="flex items-center gap-2 py-1 px-2 rounded-lg hover:bg-muted/50">
                            <MapPinIcon className="w-3 h-3 text-muted-foreground" />
                            <span className="text-sm flex-1">{city.name}</span>
                            <Button
                              variant="ghost"
                              size="sm"
                              className="cursor-pointer h-6 w-6 p-0 text-destructive"
                              onClick={() => deleteCity({ cityId: city._id as Id<"cities"> }).then(() => toast.success(t("geo.city_deleted"))).catch(() => toast.error(t("geo.delete_error")))}
                            >
                              <Trash2Icon className="w-3 h-3" />
                            </Button>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Cities Card */}
      <Card>
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between">
            <CardTitle className="text-base flex items-center gap-2">
              <MapPinIcon className="w-4 h-4" /> {t("geo.add_cities")}
            </CardTitle>
            <Button size="sm" className="cursor-pointer" onClick={() => setShowAddCity(true)}>
              <PlusIcon className="w-4 h-4 mr-1" /> {t("geo.add_city")}
            </Button>
          </div>
        </CardHeader>
      </Card>

      {/* Add Country Dialog */}
      <Dialog open={showAddCountry} onOpenChange={setShowAddCountry}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>{t("geo.add_country_title")}</DialogTitle>
            <DialogDescription>{t("geo.add_country_desc")}</DialogDescription>
          </DialogHeader>
          <div className="space-y-3 py-2">
            <div className="space-y-1.5">
              <Label>{t("geo.country_name")} *</Label>
              <Input value={countryName} onChange={(e) => setCountryName(e.target.value)} placeholder="e.g. Cameroon" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setShowAddCountry(false)} className="cursor-pointer">{tc("buttons.cancel")}</Button>
            <Button onClick={handleAddCountry} disabled={loading || !countryName.trim()} className="cursor-pointer">
              {loading ? t("geo.adding") : t("geo.add_country")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Add City Dialog */}
      <Dialog open={showAddCity} onOpenChange={setShowAddCity}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>{t("geo.add_city_title")}</DialogTitle>
            <DialogDescription>{t("geo.add_city_desc")}</DialogDescription>
          </DialogHeader>
          <div className="space-y-3 py-2">
            <div className="space-y-1.5">
              <Label>{t("geo.select_country")} *</Label>
              <Select value={selectedCountryId} onValueChange={setSelectedCountryId}>
                <SelectTrigger><SelectValue placeholder={t("geo.select_country")} /></SelectTrigger>
                <SelectContent>
                  {countries?.map((c) => (
                    <SelectItem key={c._id} value={c._id}>{c.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>{t("geo.city_name")} *</Label>
              <Input value={cityName} onChange={(e) => setCityName(e.target.value)} placeholder="e.g. Douala" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setShowAddCity(false)} className="cursor-pointer">{tc("buttons.cancel")}</Button>
            <Button onClick={handleAddCity} disabled={loading || !cityName.trim() || !selectedCountryId} className="cursor-pointer">
              {loading ? t("geo.adding") : t("geo.add_city")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

// ─── Roles & Permissions Tab ─────────────────────────────────────────────────

function RolesTab() {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const roles = useQuery(api.roleManagement.listRoles, {});
  const permissions = useQuery(api.roleManagement.getAvailablePermissions, {});
  const builtinPerms = useQuery(api.roleManagement.getBuiltinRolePermissions, {});
  const createRole = useMutation(api.roleManagement.createRole);
  const updateRoleMut = useMutation(api.roleManagement.updateRole);
  const deleteRoleMut = useMutation(api.roleManagement.deleteRole);
  const setBuiltinPerms = useMutation(api.roleManagement.setBuiltinRolePermissions);

  const [showAdd, setShowAdd] = useState(false);
  const [roleName, setRoleName] = useState("");
  const [selectedPerms, setSelectedPerms] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);
  const [editingRoleId, setEditingRoleId] = useState<string | null>(null);
  const [editPerms, setEditPerms] = useState<string[]>([]);
  // For built-in role editing
  const [editingBuiltinRole, setEditingBuiltinRole] = useState<string | null>(null);
  const [builtinEditPerms, setBuiltinEditPerms] = useState<string[]>([]);

  const handleAddRole = async () => {
    if (!roleName.trim()) return;
    setLoading(true);
    try {
      await createRole({ name: roleName.trim(), permissions: selectedPerms });
      toast.success(t("roles.created"));
      setRoleName("");
      setSelectedPerms([]);
      setShowAdd(false);
    } catch {
      toast.error(t("roles.create_error"));
    } finally {
      setLoading(false);
    }
  };

  const handleUpdatePerms = async (roleId: string) => {
    setLoading(true);
    try {
      await updateRoleMut({ roleId: roleId as Id<"roles">, permissions: editPerms });
      toast.success(t("roles.updated"));
      setEditingRoleId(null);
    } catch {
      toast.error(t("roles.update_error"));
    } finally {
      setLoading(false);
    }
  };

  const handleDelete = async (roleId: string) => {
    try {
      await deleteRoleMut({ roleId: roleId as Id<"roles"> });
      toast.success(t("roles.deleted"));
    } catch {
      toast.error(t("roles.delete_error"));
    }
  };

  const handleSaveBuiltinPerms = async (role: string) => {
    setLoading(true);
    try {
      await setBuiltinPerms({ role, permissions: builtinEditPerms });
      toast.success(t("roles.perms_updated", { role: role.charAt(0).toUpperCase() + role.slice(1) }));
      setEditingBuiltinRole(null);
    } catch {
      toast.error(t("roles.update_error"));
    } finally {
      setLoading(false);
    }
  };

  const togglePerm = (perm: string, list: string[], setList: (v: string[]) => void) => {
    if (list.includes(perm)) {
      setList(list.filter((p) => p !== perm));
    } else {
      setList([...list, perm]);
    }
  };

  const formatPerm = (perm: string) => perm.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());

  const BUILTIN_ROLE_COLORS: Record<string, string> = {
    owner: "text-orange-600 bg-orange-500/10 border-orange-500/30",
    seller: "text-emerald-600 bg-emerald-500/10 border-emerald-500/30",
    traveler: "text-blue-600 bg-blue-500/10 border-blue-500/30",
  };

  return (
    <div className="space-y-4">
      {/* Built-in Roles - Editable */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <ShieldIcon className="w-4 h-4" /> {t("roles.builtin_title")}
          </CardTitle>
          <p className="text-xs text-muted-foreground mt-1">
            {t("roles.builtin_desc")}
          </p>
        </CardHeader>
        <CardContent>
          {builtinPerms === undefined ? (
            <div className="space-y-2">
              {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-16 w-full rounded-xl" />)}
            </div>
          ) : (
            <div className="space-y-3">
              {builtinPerms.map((bp) => {
                const isEditing = editingBuiltinRole === bp.role;
                const colorCls = BUILTIN_ROLE_COLORS[bp.role] ?? "";
                return (
                  <div key={bp.role} className="rounded-xl border p-4 space-y-3">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <span className={cn("text-xs font-bold px-2.5 py-1 rounded-full border", colorCls)}>
                          {bp.role.charAt(0).toUpperCase() + bp.role.slice(1)}
                        </span>
                        <span className="text-xs text-muted-foreground">
                          {t("roles.permissions_count", { count: bp.permissions.length })}
                        </span>
                      </div>
                      <Button
                        variant="ghost"
                        size="sm"
                        className="h-7 text-xs cursor-pointer"
                        onClick={() => {
                          if (isEditing) {
                            setEditingBuiltinRole(null);
                          } else {
                            setEditingBuiltinRole(bp.role);
                            setBuiltinEditPerms([...bp.permissions]);
                          }
                        }}
                      >
                        {isEditing ? tc("buttons.cancel") : t("roles.edit_permissions")}
                      </Button>
                    </div>

                    {/* Display current permissions */}
                    {!isEditing && (
                      <div className="flex flex-wrap gap-1.5">
                        {bp.permissions.length === 0 ? (
                          <span className="text-xs text-muted-foreground italic">{t("roles.no_permissions")}</span>
                        ) : (
                          bp.permissions.map((p) => (
                            <span
                              key={p}
                              className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-primary/10 text-primary border border-primary/20"
                            >
                              {formatPerm(p)}
                            </span>
                          ))
                        )}
                      </div>
                    )}

                    {/* Edit permissions grid */}
                    {isEditing && (
                      <div className="space-y-3">
                        <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                          {(permissions ?? []).map((perm) => {
                            const isChecked = builtinEditPerms.includes(perm);
                            return (
                              <button
                                key={perm}
                                type="button"
                                onClick={() => togglePerm(perm, builtinEditPerms, setBuiltinEditPerms)}
                                className={cn(
                                  "flex items-center gap-2 text-xs px-3 py-2 rounded-lg border transition-colors cursor-pointer",
                                  isChecked
                                    ? "bg-primary/10 border-primary/30 text-primary"
                                    : "bg-muted/50 border-border text-muted-foreground hover:bg-muted",
                                )}
                              >
                                {isChecked && <CheckIcon className="w-3 h-3 shrink-0" />}
                                {formatPerm(perm)}
                              </button>
                            );
                          })}
                        </div>
                        <Button
                          size="sm"
                          className="cursor-pointer"
                          disabled={loading}
                          onClick={() => handleSaveBuiltinPerms(bp.role)}
                        >
                          {loading ? tc("buttons.saving") : t("roles.save_permissions")}
                        </Button>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Custom Roles List */}
      <Card>
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between">
            <CardTitle className="text-base flex items-center gap-2">
              <KeyIcon className="w-4 h-4" /> {t("roles.custom_title")}
            </CardTitle>
            <Button size="sm" className="cursor-pointer" onClick={() => setShowAdd(true)}>
              <PlusIcon className="w-4 h-4 mr-1" /> {t("roles.add_role")}
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          {roles === undefined ? (
            <div className="space-y-2">
              {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-12 w-full rounded-xl" />)}
            </div>
          ) : roles.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground text-sm">
              {t("roles.no_custom")}
            </div>
          ) : (
            <div className="space-y-2">
              {roles.map((role) => {
                const isEditing = editingRoleId === role._id;
                return (
                  <div key={role._id} className="rounded-xl border p-4 space-y-3">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <KeyIcon className="w-4 h-4 text-primary" />
                        <span className="font-semibold text-sm">{role.name}</span>
                        <span className="text-xs text-muted-foreground">
                          {t("roles.permissions_count", { count: role.permissions.length })}
                        </span>
                      </div>
                      <div className="flex items-center gap-1">
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-7 text-xs cursor-pointer"
                          onClick={() => {
                            if (isEditing) {
                              setEditingRoleId(null);
                            } else {
                              setEditingRoleId(role._id);
                              setEditPerms(role.permissions);
                            }
                          }}
                        >
                          {isEditing ? tc("buttons.cancel") : t("roles.edit_permissions")}
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-7 text-xs cursor-pointer text-destructive"
                          onClick={() => handleDelete(role._id)}
                        >
                          <Trash2Icon className="w-3 h-3" />
                        </Button>
                      </div>
                    </div>

                    {/* Permission badges */}
                    {!isEditing && (
                      <div className="flex flex-wrap gap-1.5">
                        {role.permissions.length === 0 ? (
                          <span className="text-xs text-muted-foreground italic">{t("roles.no_permissions")}</span>
                        ) : (
                          role.permissions.map((p) => (
                            <span
                              key={p}
                              className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-primary/10 text-primary border border-primary/20"
                            >
                              {formatPerm(p)}
                            </span>
                          ))
                        )}
                      </div>
                    )}

                    {/* Edit permissions */}
                    {isEditing && (
                      <div className="space-y-3">
                        <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                          {(permissions ?? []).map((perm) => {
                            const isChecked = editPerms.includes(perm);
                            return (
                              <button
                                key={perm}
                                type="button"
                                onClick={() => togglePerm(perm, editPerms, setEditPerms)}
                                className={cn(
                                  "flex items-center gap-2 text-xs px-3 py-2 rounded-lg border transition-colors cursor-pointer",
                                  isChecked
                                    ? "bg-primary/10 border-primary/30 text-primary"
                                    : "bg-muted/50 border-border text-muted-foreground hover:bg-muted",
                                )}
                              >
                                {isChecked && <CheckIcon className="w-3 h-3 shrink-0" />}
                                {formatPerm(perm)}
                              </button>
                            );
                          })}
                        </div>
                        <Button
                          size="sm"
                          className="cursor-pointer"
                          disabled={loading}
                          onClick={() => handleUpdatePerms(role._id)}
                        >
                          {loading ? tc("buttons.saving") : t("roles.save_permissions")}
                        </Button>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Add Role Dialog */}
      <Dialog open={showAdd} onOpenChange={setShowAdd}>
        <DialogContent className="max-w-md max-h-[85vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{t("roles.create_title")}</DialogTitle>
            <DialogDescription>{t("roles.create_desc")}</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-1.5">
              <Label>{t("roles.role_name")} *</Label>
              <Input value={roleName} onChange={(e) => setRoleName(e.target.value)} placeholder="e.g. Regional Manager" />
            </div>
            <div className="space-y-1.5">
              <Label>{t("roles.permissions_label")}</Label>
              <div className="grid grid-cols-2 gap-2">
                {(permissions ?? []).map((perm) => {
                  const isChecked = selectedPerms.includes(perm);
                  return (
                    <button
                      key={perm}
                      type="button"
                      onClick={() => togglePerm(perm, selectedPerms, setSelectedPerms)}
                      className={cn(
                        "flex items-center gap-2 text-xs px-3 py-2 rounded-lg border transition-colors cursor-pointer text-left",
                        isChecked
                          ? "bg-primary/10 border-primary/30 text-primary"
                          : "bg-muted/50 border-border text-muted-foreground hover:bg-muted",
                      )}
                    >
                      {isChecked && <CheckIcon className="w-3 h-3 shrink-0" />}
                      {formatPerm(perm)}
                    </button>
                  );
                })}
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setShowAdd(false)} className="cursor-pointer">{tc("buttons.cancel")}</Button>
            <Button onClick={handleAddRole} disabled={loading || !roleName.trim()} className="cursor-pointer">
              {loading ? t("roles.creating") : t("roles.add_role")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

// ─── Contact / WhatsApp Settings Tab ────────────────────────────────────────────

function ContactSettingsTab() {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const allCompanies = useQuery(api.companies.listAllCompanies, {});
  const contactOptions = useQuery(api.contact.getContactOptions, {});
  const inquiries = useQuery(api.contact.listInquiries, {});
  const setWhatsapp = useMutation(api.contact.setWhatsappNumber);
  const updateStatus = useMutation(api.contact.updateInquiryStatus);

  const [platformNumber, setPlatformNumber] = useState("");
  const [companyId, setCompanyId] = useState("");
  const [companyNumber, setCompanyNumber] = useState("");
  const [loading, setLoading] = useState(false);

  // Sync platform number from server
  const currentPlatform = contactOptions?.platformWhatsapp ?? "";

  const handleSavePlatform = async () => {
    if (!platformNumber.trim()) return;
    setLoading(true);
    try {
      await setWhatsapp({ scope: "platform", whatsappNumber: platformNumber.trim() });
      toast.success(t("contact_settings.saved", { defaultValue: "WhatsApp number saved" }));
    } catch {
      toast.error(t("contact_settings.save_error", { defaultValue: "Failed to save" }));
    } finally {
      setLoading(false);
    }
  };

  const handleSaveCompany = async () => {
    if (!companyId || !companyNumber.trim()) return;
    setLoading(true);
    try {
      await setWhatsapp({ scope: companyId, whatsappNumber: companyNumber.trim() });
      toast.success(t("contact_settings.saved", { defaultValue: "WhatsApp number saved" }));
      setCompanyId("");
      setCompanyNumber("");
    } catch {
      toast.error(t("contact_settings.save_error", { defaultValue: "Failed to save" }));
    } finally {
      setLoading(false);
    }
  };

  const handleResolve = async (id: string) => {
    try {
      await updateStatus({ inquiryId: id as Id<"contactInquiries">, status: "resolved" });
      toast.success(t("contact_settings.inquiry_resolved", { defaultValue: "Marked as resolved" }));
    } catch {
      toast.error(t("contact_settings.resolve_error", { defaultValue: "Failed to update" }));
    }
  };

  return (
    <div className="space-y-4">
      {/* Platform WhatsApp */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <MessageCircleIcon className="w-4 h-4" />
            {t("contact_settings.platform_title", { defaultValue: "Platform WhatsApp" })}
          </CardTitle>
          <p className="text-xs text-muted-foreground mt-1">
            {t("contact_settings.platform_desc", { defaultValue: "Set the WhatsApp number for Tibus platform inquiries" })}
          </p>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex items-center gap-2">
            <Input
              value={platformNumber || currentPlatform}
              onChange={(e) => setPlatformNumber(e.target.value)}
              placeholder="+237 6XX XXX XXX"
              className="flex-1"
            />
            <Button
              size="sm"
              className="cursor-pointer"
              disabled={loading}
              onClick={handleSavePlatform}
            >
              {tc("buttons.save")}
            </Button>
          </div>
          {currentPlatform && (
            <p className="text-xs text-muted-foreground">
              {t("contact_settings.current", { defaultValue: "Current" })}: <span className="font-medium text-foreground">{currentPlatform}</span>
            </p>
          )}
        </CardContent>
      </Card>

      {/* Per-Company WhatsApp */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base flex items-center gap-2">
            <BuildingIcon className="w-4 h-4" />
            {t("contact_settings.company_title", { defaultValue: "Company WhatsApp Numbers" })}
          </CardTitle>
          <p className="text-xs text-muted-foreground mt-1">
            {t("contact_settings.company_desc", { defaultValue: "Set a WhatsApp number for each company" })}
          </p>
        </CardHeader>
        <CardContent className="space-y-3">
          {/* Existing company numbers */}
          {contactOptions?.companies && contactOptions.companies.length > 0 && (
            <div className="space-y-2 mb-4">
              {contactOptions.companies.map((c) => (
                <div key={c.companyId} className="flex items-center gap-3 p-3 rounded-xl bg-muted/50">
                  <BuildingIcon className="w-4 h-4 text-primary shrink-0" />
                  <div className="flex-1 min-w-0">
                    <div className="font-medium text-sm">{c.companyName}</div>
                    <div className="text-xs text-muted-foreground">{c.whatsappNumber}</div>
                  </div>
                </div>
              ))}
            </div>
          )}

          {/* Add/Update company number */}
          <div className="space-y-2">
            <Select value={companyId} onValueChange={setCompanyId}>
              <SelectTrigger>
                <SelectValue placeholder={t("contact_settings.select_company", { defaultValue: "Select company" })} />
              </SelectTrigger>
              <SelectContent>
                {allCompanies?.map((c) => (
                  <SelectItem key={c._id} value={c._id}>{c.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <div className="flex items-center gap-2">
              <Input
                value={companyNumber}
                onChange={(e) => setCompanyNumber(e.target.value)}
                placeholder="+237 6XX XXX XXX"
                className="flex-1"
              />
              <Button
                size="sm"
                className="cursor-pointer"
                disabled={loading || !companyId || !companyNumber.trim()}
                onClick={handleSaveCompany}
              >
                {tc("buttons.save")}
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Recent Inquiries */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">
            {t("contact_settings.inquiries_title", { defaultValue: "Contact Inquiries" })}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {inquiries === undefined ? (
            <div className="space-y-2">
              {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-14 w-full rounded-xl" />)}
            </div>
          ) : inquiries.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground text-sm">
              {t("contact_settings.no_inquiries", { defaultValue: "No inquiries yet" })}
            </div>
          ) : (
            <div className="space-y-2">
              {inquiries.map((inq) => (
                <div key={inq._id} className="p-3 rounded-xl border hover:bg-muted/30 transition-colors space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                      <div className="font-medium text-sm">{inq.name}</div>
                      <div className="text-xs text-muted-foreground">{inq.email} {inq.phone ? `· ${inq.phone}` : ""}</div>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className={cn(
                        "text-[10px] font-semibold px-2 py-0.5 rounded-full border",
                        inq.status === "new" ? "bg-blue-500/10 text-blue-600 border-blue-500/30" :
                        inq.status === "resolved" ? "bg-green-500/10 text-green-600 border-green-500/30" :
                        "bg-muted text-muted-foreground border-border"
                      )}>
                        {inq.status}
                      </span>
                      {inq.status !== "resolved" && (
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-6 text-[10px] cursor-pointer"
                          onClick={() => handleResolve(inq._id)}
                        >
                          <CheckIcon className="w-3 h-3" />
                        </Button>
                      )}
                    </div>
                  </div>
                  <p className="text-xs text-muted-foreground bg-muted/50 p-2 rounded-lg">{inq.message}</p>
                  <p className="text-[10px] text-muted-foreground">
                    {t("contact_settings.to", { defaultValue: "To" })}: {inq.inquiryTo === "platform" ? "Tibus Platform" : inq.inquiryTo}
                  </p>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
