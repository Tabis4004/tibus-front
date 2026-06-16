import { useCallback, useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  CheckIcon,
  HistoryIcon,
  PercentIcon,
  RefreshCwIcon,
  WalletIcon,
  XIcon,
} from "lucide-react";
import { toast } from "sonner";
import { useAppUser } from "@/hooks/use-app-user.ts";
import {
  STAKEHOLDER_COUNTRY_ROLES,
  initiateStakeholderCommissionSettlementSupabase,
  listStakeholderCommissionBalancesSupabase,
  listStakeholderRevenueSharingSupabase,
  listStakeholderCommissionSettlementHistorySupabase,
  listStakeholderCommissionSettingsSupabase,
  computeStakeholderTicketSimulation,
  rejectStakeholderCommissionSettlementSupabase,
  listStakeholderCountryUsersSupabase,
  listStakeholderCountryCompaniesSupabase,
  upsertStakeholderCommissionSettingSupabase,
  upsertStakeholderPayoutMinimumSupabase,
  type StakeholderCommissionBalance,
  type StakeholderCommissionSetting,
  type StakeholderCommissionSettlement,
  type StakeholderCountryUser,
  type StakeholderRevenueSharingRow,
  type StakeholderRole,
} from "@/lib/supabase/stakeholder-commissions.ts";
import {
  type CommissionSetting,
  resolveCompanyPlatformCommission,
} from "@/lib/supabase/accounting.ts";
import { recordPlatformAuditSupabase } from "@/lib/supabase/platform-audit-log.ts";
import { parseFeeInputOrZero } from "@/lib/fee-input.ts";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
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
import {
  confirmStakeholderCommissionSettlementSupabase,
  uploadStakeholderPaymentProof,
  getStakeholderPaymentProofUrl,
} from "@/lib/supabase/stakeholder-commissions.ts";
import StakeholderSettlementApprovalFields from "./StakeholderSettlementApprovalFields.tsx";
import { cn } from "@/lib/utils.ts";

type CountryOption = { id: string; name: string };
type CompanyOption = {
  id: string;
  name: string;
  countryId: string | null;
  recruitedByUserId?: string | null;
  commissionRate?: number | null;
};

type CompanyRecruiterDraft = {
  rate: string;
  beneficiaryId: string;
  settingId: string | null;
};

function buildEmptyRateDrafts(): Record<string, string> {
  return Object.fromEntries(STAKEHOLDER_COUNTRY_ROLES.map((role) => [role, "0"]));
}

const STAKEHOLDER_ROLE_USER_FILTER: Partial<Record<StakeholderRole, string[]>> = {
  recruiter: ["admin_pays", "owner"],
};

/** Rôles pays : pas de bénéficiaire fixe — répartition automatique par vente / rôle. */
const STAKEHOLDER_ROLE_POOL_ROLES: StakeholderRole[] = ["admin_pays", "master", "seller"];

function rolePoolLabel(role: StakeholderRole, t: (key: string, opts?: { defaultValue?: string }) => string) {
  switch (role) {
    case "platform":
      return t("stakeholder_commissions.platform_pool");
    case "admin_pays":
      return t("stakeholder_commissions.admin_pays_pool", {
        defaultValue: "Réparti entre les admins pays du pays",
      });
    case "master":
      return t("stakeholder_commissions.master_pool", {
        defaultValue: "Master du vendeur (par vente)",
      });
    case "seller":
      return t("stakeholder_commissions.seller_pool", {
        defaultValue: "Vendeurs plateforme (par vente)",
      });
    default:
      return "—";
  }
}

function recruiterLabel(
  userId: string | null | undefined,
  users: StakeholderCountryUser[],
): string {
  if (!userId) return "—";
  const user = users.find((row) => row.userId === userId);
  return user?.fullName ?? user?.email ?? userId;
}

function usersForStakeholderRole(
  role: StakeholderRole,
  users: StakeholderCountryUser[],
): StakeholderCountryUser[] {
  const allowed = STAKEHOLDER_ROLE_USER_FILTER[role];
  if (!allowed?.length) return users;
  const matched = users.filter((user) => user.roles.some((name) => allowed.includes(name)));
  return matched.length > 0 ? matched : users;
}

function formatMoney(value: number, currency: string) {
  return `${value.toLocaleString(undefined, { maximumFractionDigits: 0 })} ${currency}`;
}

function statusVariant(status: StakeholderCommissionSettlement["status"]) {
  if (status === "confirmed") return "default" as const;
  if (status === "pending_confirmation") return "secondary" as const;
  if (status === "rejected") return "destructive" as const;
  return "outline" as const;
}

export default function StakeholderCommissionPanel({
  countries,
  companies = [],
  commissionSettings = [],
  onCommissionSettingsChanged,
  embedded = false,
  enabled = true,
}: {
  countries: CountryOption[];
  companies?: CompanyOption[];
  commissionSettings?: CommissionSetting[];
  onCommissionSettingsChanged?: () => void;
  embedded?: boolean;
  enabled?: boolean;
}) {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");
  const appUser = useAppUser();
  const isSuperAdmin = appUser.isSuperAdmin;
  const isCountryAdmin = appUser.roles.includes("admin_pays");
  const canManageStakeholderRates = isSuperAdmin || isCountryAdmin;

  const defaultCountryId = useMemo(() => {
    const profileCountry = appUser.profile?.countryId;
    if (profileCountry && countries.some((country) => country.id === profileCountry)) {
      return profileCountry;
    }
    const companyCountry = companies.find((company) => company.countryId)?.countryId;
    if (companyCountry && countries.some((country) => country.id === companyCountry)) {
      return companyCountry;
    }
    return countries[0]?.id ?? "";
  }, [appUser.profile?.countryId, companies, countries]);

  const [countryId, setCountryId] = useState(defaultCountryId);
  const [companyFilterId, setCompanyFilterId] = useState<string>("__all");
  const [panelCompanies, setPanelCompanies] = useState<CompanyOption[]>([]);
  const [companiesLoading, setCompaniesLoading] = useState(false);
  const [companiesError, setCompaniesError] = useState<string | null>(null);
  const [settings, setSettings] = useState<StakeholderCommissionSetting[] | undefined>(undefined);
  const [rateDrafts, setRateDrafts] = useState<Record<string, string>>(buildEmptyRateDrafts);
  const [beneficiaryDrafts, setBeneficiaryDrafts] = useState<Record<string, string>>(buildEmptyRateDrafts);
  const [minPayoutDrafts, setMinPayoutDrafts] = useState<Record<string, string>>(buildEmptyRateDrafts);
  const [countryUsers, setCountryUsers] = useState<StakeholderCountryUser[]>([]);
  const [countryUsersLoading, setCountryUsersLoading] = useState(false);
  const [countryUsersError, setCountryUsersError] = useState<string | null>(null);
  const [companyRecruiterDrafts, setCompanyRecruiterDrafts] = useState<
    Record<string, CompanyRecruiterDraft>
  >({});

  const activeCountryId = useMemo(
    () => countryId || defaultCountryId || countries[0]?.id || "",
    [countryId, defaultCountryId, countries],
  );
  const countryCompanies = useMemo(() => {
    const byId = new Map(companies.map((company) => [company.id, company]));
    return panelCompanies
      .filter((company) => company.countryId === activeCountryId)
      .map((company) => {
        const fromParent = byId.get(company.id);
        return {
          ...company,
          commissionRate: fromParent?.commissionRate ?? company.commissionRate ?? null,
          recruitedByUserId: company.recruitedByUserId ?? fromParent?.recruitedByUserId ?? null,
        };
      });
  }, [activeCountryId, companies, panelCompanies]);

  const selectedCompany = useMemo(
    () =>
      companyFilterId === "__all"
        ? null
        : countryCompanies.find((company) => company.id === companyFilterId) ?? null,
    [companyFilterId, countryCompanies],
  );

  const simulationCompany = selectedCompany ?? countryCompanies[0] ?? null;
  const simulationCommission = simulationCompany
    ? resolveCompanyPlatformCommission(simulationCompany, commissionSettings)
    : null;

  const activeCountryName = useMemo(
    () => countries.find((country) => country.id === activeCountryId)?.name ?? "",
    [activeCountryId, countries],
  );

  useEffect(() => {
    if (!activeCountryId || !canManageStakeholderRates) {
      setPanelCompanies([]);
      setCompaniesError(null);
      return;
    }

    setCompaniesLoading(true);
    setCompaniesError(null);
    let cancelled = false;

    void listStakeholderCountryCompaniesSupabase(activeCountryId)
      .then((rows) => {
        if (cancelled) return;
        setPanelCompanies(
          rows.map((row) => ({
            id: row.id,
            name: row.name,
            countryId: row.countryId,
            recruitedByUserId: row.recruitedByUserId,
          })),
        );
        setCompaniesError(null);
      })
      .catch((err) => {
        if (cancelled) return;
        setPanelCompanies([]);
        const message =
          err instanceof Error
            ? err.message
            : t("stakeholder_commissions.companies_load_error", {
                defaultValue: "Impossible de charger les compagnies pour ce pays.",
              });
        setCompaniesError(message);
        toast.error(message);
      })
      .finally(() => {
        if (!cancelled) setCompaniesLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [activeCountryId, canManageStakeholderRates, t]);

  const [balances, setBalances] = useState<StakeholderCommissionBalance[] | undefined>(undefined);
  const [balancesError, setBalancesError] = useState<string | null>(null);
  const [history, setHistory] = useState<StakeholderCommissionSettlement[] | undefined>(undefined);
  const [previewTickets, setPreviewTickets] = useState("100");
  const [previewAvgTicket, setPreviewAvgTicket] = useState("8000");
  const [previewCommissionRate, setPreviewCommissionRate] = useState("5");
  const [revenueSharing, setRevenueSharing] = useState<StakeholderRevenueSharingRow[] | undefined>(
    undefined,
  );
  const [customLabel, setCustomLabel] = useState("");
  const [customBeneficiaryId, setCustomBeneficiaryId] = useState("");
  const [customRate, setCustomRate] = useState("0");
  const [busyKey, setBusyKey] = useState<string | null>(null);
  const [savingSettings, setSavingSettings] = useState(false);

  useEffect(() => {
    if (simulationCommission) {
      setPreviewCommissionRate(String(simulationCommission.rate));
    }
  }, [simulationCommission?.rate, simulationCompany?.id]);

  useEffect(() => {
    if (defaultCountryId) setCountryId(defaultCountryId);
  }, [defaultCountryId]);

  useEffect(() => {
    if (!canManageStakeholderRates || !activeCountryId) {
      setCountryUsers([]);
      setCountryUsersError(null);
      return;
    }
    setCountryUsersLoading(true);
    setCountryUsersError(null);
    void listStakeholderCountryUsersSupabase(activeCountryId)
      .then((users) => {
        setCountryUsers(users);
        setCountryUsersError(null);
      })
      .catch((err) => {
        setCountryUsers([]);
        const message =
          err instanceof Error
            ? err.message
            : t("stakeholder_commissions.users_load_error", {
                defaultValue: "Impossible de charger les utilisateurs pour ce pays.",
              });
        setCountryUsersError(message);
        toast.error(message);
      })
      .finally(() => setCountryUsersLoading(false));
  }, [activeCountryId, canManageStakeholderRates, t]);

  const loadRevenueSharing = useCallback(() => {
    if (!activeCountryId) {
      setRevenueSharing([]);
      return;
    }
    setRevenueSharing(undefined);
    void listStakeholderRevenueSharingSupabase({
      countryId: activeCountryId,
      companyId: companyFilterId === "__all" ? null : companyFilterId,
    })
      .then(setRevenueSharing)
      .catch((err) => {
        setRevenueSharing([]);
        toast.error(
          err instanceof Error
            ? err.message
            : t("stakeholder_commissions.revenue_load_error", {
                defaultValue: "Impossible de charger le partage des revenus.",
              }),
        );
      });
  }, [activeCountryId, companyFilterId, t]);

  const loadSettings = useCallback(() => {
    setSettings(undefined);
    void listStakeholderCommissionSettingsSupabase(activeCountryId)
      .then((rows) => {
        const countryRows = rows.filter(
          (row) =>
            row.scope === "country" &&
            row.countryId === activeCountryId &&
            row.stakeholderRole !== "custom",
        );
        const companyRecruiterRows = rows.filter(
          (row) =>
            row.scope === "company" &&
            row.countryId === activeCountryId &&
            row.stakeholderRole === "recruiter",
        );

        setSettings(countryRows);

        const rates = buildEmptyRateDrafts();
        const beneficiaries = buildEmptyRateDrafts();
        for (const row of countryRows) {
          if (!STAKEHOLDER_COUNTRY_ROLES.includes(row.stakeholderRole)) continue;
          rates[row.stakeholderRole] = String(row.rate);
          if (row.beneficiaryUserId) {
            beneficiaries[row.stakeholderRole] = row.beneficiaryUserId;
          }
        }
        setRateDrafts(rates);
        setBeneficiaryDrafts(beneficiaries);

        const recruiterDrafts: Record<string, CompanyRecruiterDraft> = {};
        for (const company of countryCompanies) {
          const setting = companyRecruiterRows.find((row) => row.companyId === company.id);
          recruiterDrafts[company.id] = {
            rate: setting ? String(setting.rate) : "0",
            beneficiaryId:
              setting?.beneficiaryUserId ?? company.recruitedByUserId ?? "",
            settingId: setting?.id ?? null,
          };
        }
        setCompanyRecruiterDrafts(recruiterDrafts);
      })
      .catch((err) => {
        setSettings([]);
        toast.error(
          err instanceof Error ? err.message : t("stakeholder_commissions.settings_load_error", { defaultValue: "Impossible de charger les taux stakeholders." }),
        );
      });
  }, [activeCountryId, countryCompanies, t]);

  const loadBalances = useCallback(() => {
    if (!activeCountryId && !isCountryAdmin) {
      setBalances([]);
      return;
    }
    setBalances(undefined);
    setBalancesError(null);
    void listStakeholderCommissionBalancesSupabase(activeCountryId || null)
      .then((rows) => {
        setBalances(rows);
        setBalancesError(null);
        const mins = buildEmptyRateDrafts();
        for (const row of rows) {
          if (row.minimumPayout > 0) {
            mins[row.stakeholderRole] = String(row.minimumPayout);
          }
        }
        setMinPayoutDrafts((current) => ({ ...current, ...mins }));
      })
      .catch((err) => {
        const message =
          err instanceof Error
            ? err.message
            : t("stakeholder_commissions.balances_load_error", {
                defaultValue: "Impossible de charger les soldes stakeholders.",
              });
        setBalances([]);
        setBalancesError(message);
        toast.error(message);
      });
  }, [activeCountryId, isCountryAdmin, t]);

  const balancesMigrationHint = useMemo(() => {
    if (!balancesError) return null;
    if (
      /list_stakeholder_commission_balances|could not find the function|schema cache|PGRST202/i.test(
        balancesError,
      )
    ) {
      return t("stakeholder_commissions.balances_migration_hint");
    }
    return null;
  }, [balancesError, t]);

  const loadHistory = useCallback(() => {
    setHistory(undefined);
    void listStakeholderCommissionSettlementHistorySupabase({
      countryId: activeCountryId || null,
      limit: 50,
    })
      .then(setHistory)
      .catch((err) => {
        setHistory([]);
        toast.error(
          err instanceof Error ? err.message : t("stakeholder_commissions.history_error", { defaultValue: "Impossible de charger l'historique des règlements." }),
        );
      });
  }, [activeCountryId, t]);

  const reloadAll = useCallback(() => {
    loadSettings();
    loadBalances();
    loadHistory();
    loadRevenueSharing();
  }, [loadBalances, loadHistory, loadRevenueSharing, loadSettings]);

  useEffect(() => {
    if (!enabled) return;
    if (!activeCountryId && countries.length === 0) return;
    reloadAll();
  }, [reloadAll, activeCountryId, enabled, countries.length]);

  const totalRate = useMemo(
    () =>
      STAKEHOLDER_COUNTRY_ROLES.reduce((sum, role) => {
        const parsed = parseFeeInputOrZero(rateDrafts[role] ?? "0");
        return sum + (parsed ?? 0);
      }, 0),
    [rateDrafts],
  );

  const maxCompanyRecruiterRate = useMemo(() => {
    let max = 0;
    for (const company of countryCompanies) {
      const parsed = parseFeeInputOrZero(companyRecruiterDrafts[company.id]?.rate ?? "0");
      if (parsed != null && parsed > max) max = parsed;
    }
    return max;
  }, [companyRecruiterDrafts, countryCompanies]);

  const pendingSettlements = useMemo(
    () => (history ?? []).filter((row) => row.status === "pending_confirmation"),
    [history],
  );

  const ticketSimulation = useMemo(() => {
    const ticketCount = parseFeeInputOrZero(previewTickets);
    const avgTicketAmount = parseFeeInputOrZero(previewAvgTicket);
    const commissionRatePct = parseFeeInputOrZero(previewCommissionRate);
    if (ticketCount == null || avgTicketAmount == null || commissionRatePct == null) {
      return null;
    }

    return computeStakeholderTicketSimulation({
      ticketCount,
      avgTicketAmount,
      commissionRatePct,
      countryId: activeCountryId || null,
      rateDrafts,
      settings: settings ?? [],
    });
  }, [
    activeCountryId,
    previewAvgTicket,
    previewCommissionRate,
    previewTickets,
    rateDrafts,
    settings,
  ]);

  const handleSaveSetting = async (role: StakeholderRole) => {
    const rate = parseFeeInputOrZero(rateDrafts[role] ?? "0");
    if (rate == null || rate < 0) {
      toast.error(t("stakeholder_commissions.invalid_rate"));
      return;
    }

    setSavingSettings(true);
    try {
      const existing = (settings ?? []).find(
        (row) => row.stakeholderRole === role && row.scope === "country",
      );
      await upsertStakeholderCommissionSettingSupabase({
        scope: "country",
        countryId: activeCountryId,
        companyId: null,
        stakeholderRole: role,
        rate,
        baseType: "platform_commission",
        isActive: rate > 0,
        beneficiaryUserId: null,
        settingId: existing?.id ?? null,
      });
      setRateDrafts((current) => ({ ...current, [role]: String(rate) }));
      if (rate <= 0) {
        setBeneficiaryDrafts((current) => ({ ...current, [role]: "" }));
      }
      toast.success(t("stakeholder_commissions.settings_saved"));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.commissions.stakeholder_attribution",
        action: "update",
        summary: `Taux ${role} → ${rate}% (country)`,
        metadata: { role, rate, scope: "country", countryId: activeCountryId },
      });
      void loadSettings();
      void loadBalances();
      void loadRevenueSharing();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.save_error"));
    } finally {
      setSavingSettings(false);
    }
  };

  const handleSaveCompanyRecruiter = async (companyId: string) => {
    const company = countryCompanies.find((row) => row.id === companyId);
    const draft = companyRecruiterDrafts[companyId] ?? {
      rate: "0",
      beneficiaryId: company?.recruitedByUserId ?? "",
      settingId: null,
    };
    const rate = parseFeeInputOrZero(draft.rate ?? "0");
    if (rate == null || rate < 0) {
      toast.error(t("stakeholder_commissions.invalid_rate"));
      return;
    }

    const beneficiaryUserId =
      draft.beneficiaryId?.trim() || company?.recruitedByUserId?.trim() || null;

    if (rate > 0 && !beneficiaryUserId) {
      toast.error(
        t("stakeholder_commissions.recruiter_required", {
          defaultValue:
            "Assignez un recruteur à la compagnie ou sélectionnez un utilisateur bénéficiaire.",
        }),
      );
      return;
    }

    setSavingSettings(true);
    try {
      await upsertStakeholderCommissionSettingSupabase({
        scope: "company",
        countryId: activeCountryId,
        companyId,
        stakeholderRole: "recruiter",
        rate,
        baseType: "platform_commission",
        isActive: rate > 0,
        beneficiaryUserId: rate > 0 ? beneficiaryUserId : null,
        settingId: draft.settingId,
      });
      toast.success(t("stakeholder_commissions.settings_saved"));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.commissions.stakeholder_attribution",
        action: "update",
        summary: `Recruteur ${company?.name ?? companyId} → ${rate}%`,
        metadata: { role: "recruiter", rate, companyId, countryId: activeCountryId },
      });
      void loadSettings();
      void loadBalances();
      void loadRevenueSharing();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.save_error"));
    } finally {
      setSavingSettings(false);
    }
  };

  const handleInitiatePayment = async (row: StakeholderCommissionBalance) => {
    const key = `pay:${row.stakeholderRole}:${row.beneficiaryUserId ?? "platform"}`;
    setBusyKey(key);
    try {
      await initiateStakeholderCommissionSettlementSupabase({
        countryId: row.countryId,
        stakeholderRole: row.stakeholderRole,
        beneficiaryUserId: row.beneficiaryUserId,
      });
      toast.success(t("stakeholder_commissions.payment_initiated"));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.commissions.stakeholder_attribution",
        action: "create",
        summary: `Paiement initié ${row.stakeholderRole} ${row.beneficiaryName ?? "plateforme"}`,
        metadata: {
          countryId: row.countryId,
          role: row.stakeholderRole,
          beneficiaryUserId: row.beneficiaryUserId,
          amount: row.balanceDue,
        },
      });
      loadBalances();
      loadHistory();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.payment_error"));
    } finally {
      setBusyKey(null);
    }
  };

  const handleConfirm = async (
    settlement: StakeholderCommissionSettlement,
    input: { approvalNote: string; proofFile: File },
  ) => {
    setBusyKey(settlement.id);
    try {
      const uploaded = await uploadStakeholderPaymentProof(settlement.countryId, input.proofFile);
      await confirmStakeholderCommissionSettlementSupabase({
        settlementId: settlement.id,
        approvalNote: input.approvalNote,
        paymentProofPath: uploaded.path,
        paymentProofFileName: uploaded.fileName,
      });
      toast.success(t("stakeholder_commissions.payment_confirmed"));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.commissions.stakeholder_attribution",
        action: "update",
        summary: `Paiement approuvé ${settlement.stakeholderRole} — ${settlement.beneficiaryName ?? "plateforme"}`,
        metadata: {
          settlementId: settlement.id,
          amount: settlement.amount,
          currency: settlement.currency,
          beneficiaryUserId: settlement.beneficiaryUserId,
          approvalNote: input.approvalNote,
          paymentProofPath: uploaded.path,
          paymentProofFileName: uploaded.fileName,
        },
      });
      loadBalances();
      loadHistory();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.confirm_error"));
    } finally {
      setBusyKey(null);
    }
  };

  const handleReject = async (settlement: StakeholderCommissionSettlement) => {
    setBusyKey(settlement.id);
    try {
      await rejectStakeholderCommissionSettlementSupabase(settlement.id);
      toast.success(t("stakeholder_commissions.payment_rejected"));
      loadBalances();
      loadHistory();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.reject_error"));
    } finally {
      setBusyKey(null);
    }
  };

  const canApproveSettlement = (settlement: StakeholderCommissionSettlement) => {
    if (settlement.status !== "pending_confirmation") return false;
    return isSuperAdmin || isCountryAdmin;
  };

  const openPaymentProof = async (path: string | null) => {
    if (!path) return;
    try {
      const url = await getStakeholderPaymentProofUrl(path);
      window.open(url, "_blank", "noopener,noreferrer");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Preuve inaccessible");
    }
  };

  const canInitiatePayment = (row: StakeholderCommissionBalance) => {
    if (row.pendingAmount > 0 || row.balanceDue <= 0) return false;
    if (row.balanceDue < row.minimumPayout) return false;
    if (isSuperAdmin || isCountryAdmin) return true;
    return row.beneficiaryUserId === appUser.profile?.id;
  };

  if (!enabled) {
    return null;
  }

  if (countries.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        {t("stakeholder_commissions.load_error")}
      </p>
    );
  }

  return (
    <div className={cn("space-y-4", embedded && "p-0")}>
      <div className="flex flex-wrap items-end gap-3">
        <div className="space-y-1.5 min-w-[200px]">
          <Label>{t("stakeholder_commissions.country")}</Label>
          <Select
            value={activeCountryId}
            onValueChange={setCountryId}
            disabled={!isSuperAdmin}
          >
            <SelectTrigger>
              <SelectValue placeholder={t("commissions.select_country", { defaultValue: "Pays" })} />
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
        <Button variant="outline" size="sm" className="gap-2" onClick={reloadAll}>
          <RefreshCwIcon className="w-4 h-4" />
          {t("stakeholder_commissions.refresh")}
        </Button>
        {countryCompanies.length > 0 ? (
          <div className="space-y-1.5 min-w-[200px]">
            <Label>
              {t("stakeholder_commissions.company_filter", {
                defaultValue: "Compagnie (filtre pays)",
              })}
            </Label>
            <Select value={companyFilterId} onValueChange={setCompanyFilterId}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="__all">
                  {t("stakeholder_commissions.all_companies", { defaultValue: "Toutes les compagnies" })}
                </SelectItem>
                {countryCompanies.map((company) => (
                  <SelectItem key={company.id} value={company.id}>
                    {company.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        ) : null}
      </div>

      <p className="text-xs text-muted-foreground">
        {t("stakeholder_commissions.realtime_hint", {
          defaultValue:
            "Le partage est calculé sur la commission plateforme de chaque compagnie (taux compagnie prioritaire). Le filtre pays sert à lister les compagnies et attribuer le % recruteur par compagnie.",
        })}
      </p>

      {simulationCommission && simulationCompany ? (
        <p className="rounded-lg border border-emerald-300/60 bg-emerald-50/80 px-3 py-2 text-sm text-emerald-900">
          {selectedCompany
            ? t("stakeholder_commissions.company_commission_active", {
                defaultValue:
                  "{{company}} : commission plateforme {{rate}} % ({{paidBy}}). Ce taux compagnie s'applique au revenue sharing, indépendamment du réglage pays.",
                company: simulationCompany.name,
                rate: simulationCommission.rate,
                paidBy:
                  simulationCommission.paidBy === "traveler"
                    ? t("commissions.paid_by_traveler_short", { defaultValue: "voyageur" })
                    : t("commissions.paid_by_company_short", { defaultValue: "compagnie" }),
              })
            : t("stakeholder_commissions.country_filter_hint", {
                defaultValue:
                  "Pays {{country}} : {{count}} compagnie(s). Sélectionnez une compagnie pour voir son taux (ex. {{example}} : {{rate}} %).",
                country: activeCountryName,
                count: countryCompanies.length,
                example: simulationCompany.name,
                rate: simulationCommission.rate,
              })}
        </p>
      ) : countryCompanies.length === 0 ? (
        <p className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900">
          {t("stakeholder_commissions.no_companies_for_recruiters", {
            country: activeCountryName || activeCountryId,
            defaultValue: "Aucune compagnie pour {{country}}.",
          })}
        </p>
      ) : null}

      {canManageStakeholderRates && (
        <div className="rounded-lg border p-3 space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="flex items-center gap-2 text-sm font-medium">
              <PercentIcon className="w-4 h-4" />
              {t("stakeholder_commissions.global_config_title", {
                defaultValue: "Paramétrage du partage (vue globale)",
              })}
            </div>
            <Badge variant="outline">
              {t("stakeholder_commissions.scope_country")}
            </Badge>
          </div>
          {appUser.isAdminSandbox && (
            <p className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900">
              {t("stakeholder_commissions.sandbox_hint", {
                defaultValue:
                  "Mode sandbox UI : les taux et utilisateurs nécessitent un rôle super_admin ou admin_pays en base. Reconnectez-vous après attribution du rôle.",
              })}
            </p>
          )}
          {countryUsersError ? (
            <p className="text-xs text-destructive">{countryUsersError}</p>
          ) : null}
          <p className="text-xs text-muted-foreground">
            {t("stakeholder_commissions.global_config_hint", {
              defaultValue:
                "Taux pays pour plateforme, admin pays, master et vendeur. Une ligne recruteur par compagnie (bénéficiaire dynamique). Un même utilisateur peut cumuler plusieurs rôles (ex. admin pays + recruteur) : chaque solde est retirable selon son seuil.",
            })}
          </p>
          {totalRate + maxCompanyRecruiterRate > 100 ? (
            <p className="text-xs text-destructive">
              {t("stakeholder_commissions.rate_overflow", {
                total: totalRate + maxCompanyRecruiterRate,
              })}
            </p>
          ) : null}
          {companiesError ? (
            <p className="text-xs text-destructive">{companiesError}</p>
          ) : null}
          {settings === undefined || companiesLoading ? (
            <Skeleton className="h-48 w-full" />
          ) : (
            <div className="overflow-x-auto rounded-lg border">
              <table className="min-w-full text-sm">
                <thead className="bg-muted/60 text-left">
                  <tr>
                    <th className="px-3 py-2">{t("stakeholder_commissions.col_scope", { defaultValue: "Scope" })}</th>
                    <th className="px-3 py-2">{t("stakeholder_commissions.col_company", { defaultValue: "Compagnie" })}</th>
                    <th className="px-3 py-2">{t("stakeholder_commissions.col_role")}</th>
                    <th className="px-3 py-2">{t("stakeholder_commissions.col_user")}</th>
                    <th className="px-3 py-2">{t("stakeholder_commissions.col_rate")}</th>
                    <th className="px-3 py-2" />
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {STAKEHOLDER_COUNTRY_ROLES.map((role) => (
                    <tr key={`country:${role}`} className="bg-muted/10">
                      <td className="px-3 py-2 text-xs text-muted-foreground">
                        {t("stakeholder_commissions.scope_country")}
                      </td>
                      <td className="px-3 py-2 text-xs text-muted-foreground">—</td>
                      <td className="px-3 py-2">
                        <div>{t(`stakeholder_commissions.roles.${role}`)}</div>
                        {(role === "master" || role === "seller") && (
                          <p className="text-[10px] text-muted-foreground mt-0.5">
                            {t("stakeholder_commissions.roles.optional_hint", {
                              defaultValue: "Optionnel — 0 % pour désactiver.",
                            })}
                          </p>
                        )}
                      </td>
                      <td className="px-3 py-2 min-w-[200px]">
                        <span className="text-xs text-muted-foreground">
                          {rolePoolLabel(role, t)}
                        </span>
                      </td>
                      <td className="px-3 py-2">
                        <Input
                          className="h-8 w-24"
                          value={rateDrafts[role] ?? "0"}
                          onChange={(e) =>
                            setRateDrafts((current) => ({ ...current, [role]: e.target.value }))
                          }
                        />
                      </td>
                      <td className="px-3 py-2">
                        <Button
                          size="sm"
                          variant="secondary"
                          disabled={savingSettings}
                          onClick={() => void handleSaveSetting(role)}
                        >
                          {tc("buttons.save")}
                        </Button>
                      </td>
                    </tr>
                  ))}

                  {countryCompanies.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="px-3 py-4 text-sm text-muted-foreground">
                        {t("stakeholder_commissions.no_companies_for_recruiters", {
                          country: activeCountryName || activeCountryId,
                          defaultValue:
                            "Aucune compagnie pour {{country}}. Choisissez Côte d'Ivoire ou Burkina Faso dans le sélecteur pays, ou créez une compagnie rattachée au pays.",
                        })}
                      </td>
                    </tr>
                  ) : (
                    countryCompanies.map((company) => {
                      const draft = companyRecruiterDrafts[company.id] ?? {
                        rate: "0",
                        beneficiaryId: company.recruitedByUserId ?? "",
                        settingId: null,
                      };
                      const defaultRecruiterId = company.recruitedByUserId ?? "";
                      return (
                        <tr key={`company:${company.id}`}>
                          <td className="px-3 py-2 text-xs">
                            {t("stakeholder_commissions.scope_company", { defaultValue: "Par compagnie" })}
                          </td>
                          <td className="px-3 py-2 font-medium">{company.name}</td>
                          <td className="px-3 py-2">
                            {t("stakeholder_commissions.roles.recruiter")}
                          </td>
                          <td className="px-3 py-2 min-w-[220px]">
                            <Select
                              value={draft.beneficiaryId || defaultRecruiterId || "__none"}
                              onValueChange={(value) =>
                                setCompanyRecruiterDrafts((current) => ({
                                  ...current,
                                  [company.id]: {
                                    ...draft,
                                    beneficiaryId: value === "__none" ? "" : value,
                                  },
                                }))
                              }
                              disabled={countryUsersLoading}
                            >
                              <SelectTrigger className="h-8">
                                <SelectValue
                                  placeholder={recruiterLabel(
                                    draft.beneficiaryId || defaultRecruiterId,
                                    countryUsers,
                                  )}
                                />
                              </SelectTrigger>
                              <SelectContent>
                                <SelectItem value="__none">—</SelectItem>
                                {defaultRecruiterId ? (
                                  <SelectItem value={defaultRecruiterId}>
                                    {recruiterLabel(defaultRecruiterId, countryUsers)}
                                    {t("stakeholder_commissions.company_recruiter_default", {
                                      defaultValue: " (fiche compagnie)",
                                    })}
                                  </SelectItem>
                                ) : null}
                                {usersForStakeholderRole("recruiter", countryUsers)
                                  .filter((user) => user.userId !== defaultRecruiterId)
                                  .map((user) => (
                                    <SelectItem key={user.userId} value={user.userId}>
                                      {user.fullName ?? user.email ?? user.userId}
                                    </SelectItem>
                                  ))}
                              </SelectContent>
                            </Select>
                          </td>
                          <td className="px-3 py-2">
                            <Input
                              className="h-8 w-24"
                              value={draft.rate}
                              onChange={(e) =>
                                setCompanyRecruiterDrafts((current) => ({
                                  ...current,
                                  [company.id]: { ...draft, rate: e.target.value },
                                }))
                              }
                            />
                          </td>
                          <td className="px-3 py-2">
                            <Button
                              size="sm"
                              variant="secondary"
                              disabled={savingSettings}
                              onClick={() => void handleSaveCompanyRecruiter(company.id)}
                            >
                              {tc("buttons.save")}
                            </Button>
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
          )}

          <div className="rounded-lg border border-dashed p-3 space-y-2">
            <p className="text-sm font-medium">
              {t("stakeholder_commissions.add_custom", { defaultValue: "Ajouter un stakeholder" })}
            </p>
            <div className="grid gap-2 md:grid-cols-4">
              <Input
                placeholder={t("stakeholder_commissions.custom_label", { defaultValue: "Libellé" })}
                value={customLabel}
                onChange={(e) => setCustomLabel(e.target.value)}
              />
              <Input
                placeholder={t("stakeholder_commissions.custom_user_id", { defaultValue: "ID utilisateur" })}
                value={customBeneficiaryId}
                onChange={(e) => setCustomBeneficiaryId(e.target.value)}
              />
              <Input
                placeholder="%"
                value={customRate}
                onChange={(e) => setCustomRate(e.target.value)}
              />
              <Button
                variant="outline"
                disabled={savingSettings || !customLabel.trim() || !customBeneficiaryId.trim()}
                onClick={() => {
                  const rate = parseFeeInputOrZero(customRate);
                  if (rate == null) {
                    toast.error(t("stakeholder_commissions.invalid_rate"));
                    return;
                  }
                  void (async () => {
                    setSavingSettings(true);
                    try {
                      await upsertStakeholderCommissionSettingSupabase({
                        scope: "country",
                        countryId: activeCountryId,
                        companyId: null,
                        stakeholderRole: "custom",
                        label: customLabel.trim(),
                        beneficiaryUserId: customBeneficiaryId.trim(),
                        rate,
                        baseType: "platform_commission",
                      });
                      toast.success(t("stakeholder_commissions.settings_saved"));
                      setCustomLabel("");
                      setCustomBeneficiaryId("");
                      setCustomRate("0");
                      reloadAll();
                    } catch (err) {
                      toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.save_error"));
                    } finally {
                      setSavingSettings(false);
                    }
                  })();
                }}
              >
                {t("stakeholder_commissions.add_custom_btn", { defaultValue: "Ajouter" })}
              </Button>
            </div>
          </div>
        </div>
      )}

      <div className="rounded-lg border p-3 space-y-3">
        <div className="flex items-center gap-2 text-sm font-medium">
          <WalletIcon className="w-4 h-4" />
          {t("stakeholder_commissions.revenue_sharing_title", { defaultValue: "Revenu sharing par compagnie" })}
        </div>
        {revenueSharing === undefined ? (
          <Skeleton className="h-32 w-full" />
        ) : revenueSharing.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("stakeholder_commissions.no_revenue", {
              defaultValue: "Aucune commission capturée pour ce filtre. Vérifiez que le taux pays est « payé par le voyageur ».",
            })}
          </p>
        ) : (
          <div className="overflow-x-auto rounded-lg border">
            <table className="min-w-full text-sm">
              <thead className="bg-muted/60 text-left">
                <tr>
                  <th className="px-3 py-2">{t("commissions.company", { defaultValue: "Compagnie" })}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_role")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_user")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_rate")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_earned")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.sim_tickets")}</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {revenueSharing.map((row) => (
                  <tr key={`${row.companyId}:${row.stakeholderRole}:${row.beneficiaryUserId ?? "x"}:${row.stakeholderLabel}`}>
                    <td className="px-3 py-2">{row.companyName}</td>
                    <td className="px-3 py-2">{row.stakeholderLabel}</td>
                    <td className="px-3 py-2">{row.beneficiaryName ?? "—"}</td>
                    <td className="px-3 py-2 tabular-nums">{row.rate} %</td>
                    <td className="px-3 py-2 tabular-nums font-medium">
                      {formatMoney(row.earnedAmount, row.currency)}
                    </td>
                    <td className="px-3 py-2 tabular-nums">{row.ticketCount}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="rounded-lg border bg-muted/20 p-3 space-y-3">
            <div>
              <p className="text-sm font-medium">{t("stakeholder_commissions.simulator_title")}</p>
              <p className="mt-0.5 text-xs text-muted-foreground">
                {simulationCompany
                  ? t("stakeholder_commissions.simulator_company_desc", {
                      defaultValue:
                        "Simulation pour {{company}} — commission compagnie {{rate}} % (le taux pays est ignoré).",
                      company: simulationCompany.name,
                      rate: simulationCommission?.rate ?? previewCommissionRate,
                    })
                  : t("stakeholder_commissions.simulator_desc")}
              </p>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div className="space-y-1">
                <Label>{t("stakeholder_commissions.sim_tickets")}</Label>
                <Input
                  className="h-8"
                  value={previewTickets}
                  onChange={(e) => setPreviewTickets(e.target.value)}
                  placeholder="100"
                />
              </div>
              <div className="space-y-1">
                <Label>{t("stakeholder_commissions.sim_avg_ticket")}</Label>
                <Input
                  className="h-8"
                  value={previewAvgTicket}
                  onChange={(e) => setPreviewAvgTicket(e.target.value)}
                  placeholder="8000"
                />
              </div>
              <div className="space-y-1">
                <Label>{t("stakeholder_commissions.sim_commission_rate")}</Label>
                <Input
                  className="h-8"
                  value={previewCommissionRate}
                  onChange={(e) => setPreviewCommissionRate(e.target.value)}
                  placeholder="8.5"
                />
              </div>
            </div>
            {ticketSimulation ? (
              <div className="space-y-3">
                <div className="grid grid-cols-2 md:grid-cols-4 gap-2 text-xs">
                  <div className="rounded-md border bg-background px-2 py-1.5">
                    <div className="text-muted-foreground">{t("stakeholder_commissions.sim_gmv")}</div>
                    <div className="font-semibold tabular-nums">
                      {formatMoney(ticketSimulation.gmv, "XOF")}
                    </div>
                  </div>
                  <div className="rounded-md border bg-background px-2 py-1.5">
                    <div className="text-muted-foreground">{t("stakeholder_commissions.sim_pool_ticket")}</div>
                    <div className="font-semibold tabular-nums">
                      {formatMoney(ticketSimulation.poolPerTicket, "XOF")}
                    </div>
                  </div>
                  <div className="rounded-md border bg-background px-2 py-1.5">
                    <div className="text-muted-foreground">{t("stakeholder_commissions.sim_pool_total")}</div>
                    <div className="font-semibold tabular-nums">
                      {formatMoney(ticketSimulation.platformCommissionAmount, "XOF")}
                    </div>
                  </div>
                  <div className="rounded-md border bg-background px-2 py-1.5">
                    <div className="text-muted-foreground">{t("stakeholder_commissions.preview_total_rate")}</div>
                    <div className="font-semibold tabular-nums">
                      {ticketSimulation.totalRatePercent.toLocaleString(undefined, {
                        maximumFractionDigits: 2,
                      })}
                      %
                    </div>
                  </div>
                </div>
                <p className="text-[11px] text-muted-foreground">
                  {t("stakeholder_commissions.sim_formula", {
                    tickets: ticketSimulation.ticketCount.toLocaleString("fr-FR"),
                    avg: ticketSimulation.avgTicketAmount.toLocaleString("fr-FR"),
                    rate: ticketSimulation.commissionRatePct,
                    pool: formatMoney(ticketSimulation.platformCommissionAmount, "XOF"),
                  })}
                </p>
                <div className="overflow-x-auto rounded-lg border">
                  <table className="min-w-full text-sm">
                    <thead className="bg-muted/60 text-left">
                      <tr>
                        <th className="px-3 py-2">{t("stakeholder_commissions.col_role")}</th>
                        <th className="px-3 py-2">{t("stakeholder_commissions.col_rate")}</th>
                        <th className="px-3 py-2">{t("stakeholder_commissions.sim_col_per_ticket")}</th>
                        <th className="px-3 py-2">{t("stakeholder_commissions.sim_col_total")}</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y">
                      {ticketSimulation.items.map((item) => (
                        <tr key={item.stakeholderRole}>
                          <td className="px-3 py-2">
                            {t(`stakeholder_commissions.roles.${item.stakeholderRole}`)}
                          </td>
                          <td className="px-3 py-2 tabular-nums">{item.rate} %</td>
                          <td className="px-3 py-2 tabular-nums">
                            {formatMoney(
                              Math.round((ticketSimulation.poolPerTicket * item.rate) / 100),
                              "XOF",
                            )}
                          </td>
                          <td className="px-3 py-2 tabular-nums font-medium">
                            {formatMoney(item.amount, "XOF")}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                {ticketSimulation.items.some(
                  (item) => item.stakeholderRole === "seller" && item.rate > 0,
                ) && (
                  <p className="text-[10px] text-muted-foreground">
                    {t("stakeholder_commissions.preview_seller_note")}
                  </p>
                )}
              </div>
            ) : (
              <p className="text-xs text-muted-foreground">
                {t("stakeholder_commissions.sim_invalid")}
              </p>
            )}
      </div>


      {isSuperAdmin && activeCountryId ? (
        <div className="rounded-lg border border-dashed p-3 space-y-2">{/* min_payout_section */}
          <p className="text-sm font-medium">
            {t("stakeholder_commissions.min_payout_title", {
              defaultValue: "Seuils minimum de demande (par rôle)",
            })}
          </p>
          <div className="grid gap-2 md:grid-cols-3">
            {STAKEHOLDER_COUNTRY_ROLES.filter((role) => role !== "platform").map((role) => (
              <div key={`min-${role}`} className="flex items-end gap-2">
                <div className="flex-1 space-y-1">
                  <Label className="text-xs">{t(`stakeholder_commissions.roles.${role}`)}</Label>
                  <Input
                    className="h-8"
                    value={minPayoutDrafts[role] ?? ""}
                    placeholder="5000"
                    onChange={(e) =>
                      setMinPayoutDrafts((current) => ({ ...current, [role]: e.target.value }))
                    }
                  />
                </div>
                <Button
                  size="sm"
                  variant="outline"
                  disabled={savingSettings}
                  onClick={() => {
                    const amount = parseFeeInputOrZero(minPayoutDrafts[role] ?? "0");
                    if (amount == null) {
                      toast.error(t("stakeholder_commissions.invalid_rate"));
                      return;
                    }
                    void (async () => {
                      setSavingSettings(true);
                      try {
                        await upsertStakeholderPayoutMinimumSupabase({
                          countryId: activeCountryId,
                          stakeholderRole: role,
                          minimumAmount: amount,
                        });
                        toast.success(t("stakeholder_commissions.settings_saved"));
                        loadBalances();
                      } catch (err) {
                        toast.error(err instanceof Error ? err.message : t("stakeholder_commissions.save_error"));
                      } finally {
                        setSavingSettings(false);
                      }
                    })();
                  }}
                >
                  {tc("buttons.save")}
                </Button>
              </div>
            ))}
          </div>
        </div>
      ) : null}

      <div className="rounded-lg border p-3 space-y-3">
        <div className="flex items-center gap-2 text-sm font-medium">
          <WalletIcon className="w-4 h-4" />
          {t("stakeholder_commissions.balances_title")}
        </div>
        {balancesError ? (
          <div className="rounded-lg border border-destructive/30 bg-destructive/5 p-3 space-y-2">
            <p className="text-sm text-destructive">{balancesError}</p>
            {balancesMigrationHint ? (
              <p className="text-xs text-muted-foreground">{balancesMigrationHint}</p>
            ) : null}
          </div>
        ) : balances === undefined ? (
          <Skeleton className="h-40 w-full" />
        ) : balances.length === 0 ? (
          <p className="text-sm text-muted-foreground">{t("stakeholder_commissions.no_balances")}</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border">
            <table className="min-w-full text-sm">
              <thead className="bg-muted/60 text-left">
                <tr>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_role")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_user")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_rate")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_earned")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_paid")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_pending")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_balance")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_minimum", { defaultValue: "Minimum" })}</th>
                  <th className="px-3 py-2" />
                </tr>
              </thead>
              <tbody className="divide-y">
                {balances.map((row) => {
                  const rowKey = `${row.stakeholderRole}:${row.beneficiaryUserId ?? "platform"}`;
                  return (
                    <tr key={rowKey}>
                      <td className="px-3 py-2">{t(`stakeholder_commissions.roles.${row.stakeholderRole}`)}</td>
                      <td className="px-3 py-2">{row.beneficiaryName ?? t("stakeholder_commissions.platform_pool")}</td>
                      <td className="px-3 py-2">{row.rate}%</td>
                      <td className="px-3 py-2 tabular-nums">{formatMoney(row.earnedAmount, row.currency)}</td>
                      <td className="px-3 py-2 tabular-nums text-emerald-700">{formatMoney(row.paidAmount, row.currency)}</td>
                      <td className="px-3 py-2 tabular-nums text-amber-700">{formatMoney(row.pendingAmount, row.currency)}</td>
                      <td className="px-3 py-2 tabular-nums font-medium">{formatMoney(row.balanceDue, row.currency)}</td>
                      <td className="px-3 py-2 tabular-nums text-muted-foreground">
                        {formatMoney(row.minimumPayout, row.currency)}
                      </td>
                      <td className="px-3 py-2">
                        {canInitiatePayment(row) && (
                          <Button
                            size="sm"
                            disabled={busyKey === `pay:${row.stakeholderRole}:${row.beneficiaryUserId ?? "platform"}`}
                            onClick={() => void handleInitiatePayment(row)}
                          >
                            {t("stakeholder_commissions.request_payout", { defaultValue: "Demander paiement" })}
                          </Button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="rounded-lg border p-3 space-y-3">
        <div className="flex items-center gap-2 text-sm font-medium">
          <HistoryIcon className="w-4 h-4" />
          {t("stakeholder_commissions.history_title")}
        </div>

        {pendingSettlements.length > 0 && (
          <div className="space-y-2">
            <p className="text-xs font-medium text-muted-foreground">{t("stakeholder_commissions.pending_validation")}</p>
            {pendingSettlements.map((settlement) => (
              <div key={settlement.id} className="flex flex-wrap items-center justify-between gap-2 rounded-md border p-2 text-sm">
                <div>
                  <span className="font-medium">{t(`stakeholder_commissions.roles.${settlement.stakeholderRole}`)}</span>
                  {" · "}
                  {settlement.beneficiaryName ?? t("stakeholder_commissions.platform_pool")}
                  {" · "}
                  {formatMoney(settlement.amount, settlement.currency)}
                </div>
                {canApproveSettlement(settlement) && (
                  <StakeholderSettlementApprovalFields
                    busy={busyKey === settlement.id}
                    onApprove={(input) => handleConfirm(settlement, input)}
                    onReject={() => handleReject(settlement)}
                  />
                )}
              </div>
            ))}
          </div>
        )}

        {history === undefined ? (
          <Skeleton className="h-32 w-full" />
        ) : history.length === 0 ? (
          <p className="text-sm text-muted-foreground">{t("stakeholder_commissions.no_history")}</p>
        ) : (
          <div className="overflow-x-auto rounded-lg border">
            <table className="min-w-full text-sm">
              <thead className="bg-muted/60 text-left">
                <tr>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_date")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_role")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_user")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_amount")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_status")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_initiated_by")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_validated_by")}</th>
                  <th className="px-3 py-2">{t("stakeholder_commissions.col_proof", { defaultValue: "Preuve" })}</th>
                </tr>
              </thead>
              <tbody className="divide-y">
                {history.map((row) => (
                  <tr key={row.id}>
                    <td className="px-3 py-2 whitespace-nowrap">{new Date(row.initiatedAt).toLocaleString()}</td>
                    <td className="px-3 py-2">{t(`stakeholder_commissions.roles.${row.stakeholderRole}`)}</td>
                    <td className="px-3 py-2">{row.beneficiaryName ?? t("stakeholder_commissions.platform_pool")}</td>
                    <td className="px-3 py-2 tabular-nums">{formatMoney(row.amount, row.currency)}</td>
                    <td className="px-3 py-2">
                      <Badge variant={statusVariant(row.status)}>
                        {t(`stakeholder_commissions.status.${row.status}`)}
                      </Badge>
                    </td>
                    <td className="px-3 py-2">{row.initiatedByName ?? "—"}</td>
                    <td className="px-3 py-2">
                      <div>{row.confirmedByName ?? row.rejectedByName ?? "—"}</div>
                      {row.approvalNote ? (
                        <p className="text-[10px] text-muted-foreground mt-0.5 max-w-xs">{row.approvalNote}</p>
                      ) : null}
                    </td>
                    <td className="px-3 py-2">
                      {row.paymentProofPath ? (
                        <Button size="sm" variant="link" className="h-auto p-0 text-xs" onClick={() => void openPaymentProof(row.paymentProofPath)}>
                          {row.paymentProofFileName ?? t("stakeholder_commissions.view_proof", { defaultValue: "Voir" })}
                        </Button>
                      ) : (
                        "—"
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
