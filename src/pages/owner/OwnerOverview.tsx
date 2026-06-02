import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import {
  BusIcon,
  BuildingIcon,
  CalendarIcon,
  UsersIcon,
  ArrowRightIcon,
  AlertCircleIcon,
  PercentIcon,
  BarChart3Icon,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { cn } from "@/lib/utils.ts";
import { motion } from "motion/react";

export default function OwnerOverview() {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const user = useQuery(api.users.getCurrentUser, {});
  const company = useQuery(api.companies.getMyCompany, {});
  const commissions = useQuery(api.commissions.getOwnerCommissions, {});
  const kpis = useQuery(api.analytics.getKPIs, {});

  if (company === undefined) {
    return (
      <div className="p-6 space-y-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-28 w-full" />
        <div className="grid grid-cols-2 gap-3">
          {Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-24 rounded-xl" />)}
        </div>
      </div>
    );
  }

  if (!company) {
    return (
      <div className="max-w-lg mx-auto px-4 py-12 text-center space-y-5">
        <div className="w-16 h-16 rounded-2xl bg-muted flex items-center justify-center mx-auto">
          <BuildingIcon className="w-8 h-8 text-muted-foreground" />
        </div>
        <div>
          <h2 className="text-xl font-bold">{t("overview.no_company")}</h2>
          <p className="text-muted-foreground text-sm mt-1">{t("overview.no_company_desc")}</p>
        </div>
        <Button asChild>
          <Link to={`/${lng}/owner/company`}>{t("overview.create_company")}</Link>
        </Button>
      </div>
    );
  }

  const stats = [
    { labelKey: "sidebar.fleet", icon: BusIcon, value: kpis?.totalBuses ?? "—", toSuffix: "/owner/buses", color: "text-primary" },
    { labelKey: "sidebar.trips", icon: CalendarIcon, value: kpis?.upcomingTrips ?? "—", toSuffix: "/owner/trips", color: "text-orange-500" },
    { labelKey: "sidebar.sellers", icon: UsersIcon, value: kpis?.totalSellers ?? "—", toSuffix: "/owner/sellers", color: "text-emerald-500" },
    { labelKey: "sidebar.analytics", icon: BarChart3Icon, value: kpis?.totalBookings ?? "—", toSuffix: "/owner/analytics", color: "text-indigo-500" },
  ];

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-6">
      {/* Welcome */}
      <motion.div
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.3, ease: "easeOut" }}
      >
        <h1 className="text-2xl font-extrabold tracking-tight">
          {user?.name ? `Hey, ${user.name.split(" ")[0]}` : t("overview.title")}
        </h1>
        <p className="text-muted-foreground text-sm mt-1">{t("overview.desc")}</p>
      </motion.div>

      {/* Subscription warning */}
      {(!company.subscriptionStatus || company.subscriptionStatus === "none") && (
        <div className="flex items-start gap-3 p-4 rounded-xl bg-orange-50 dark:bg-orange-950/30 border border-orange-200 dark:border-orange-900">
          <AlertCircleIcon className="w-5 h-5 text-orange-500 shrink-0 mt-0.5" />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-orange-700 dark:text-orange-400">{t("overview.no_subscription")}</p>
            <p className="text-xs text-orange-600/80 dark:text-orange-400/70 mt-0.5">{t("overview.no_subscription_desc")}</p>
          </div>
          <Button size="sm" variant="secondary" className="shrink-0 text-xs cursor-pointer" asChild>
            <Link to={`/${lng}/owner/subscription`}>{t("overview.view_plans")}</Link>
          </Button>
        </div>
      )}

      {/* Company Card */}
      <Card className="pt-0 overflow-hidden">
        <div className="h-24 bg-gradient-to-br from-primary/20 to-primary/5" />
        <CardContent className="pt-0 -mt-8 pb-5">
          <div className="flex items-end gap-4">
            <div className="w-16 h-16 rounded-2xl border-4 border-background bg-primary/10 flex items-center justify-center shrink-0 overflow-hidden">
              {company.logoUrl ? (
                <img src={company.logoUrl} alt="logo" className="w-full h-full object-cover" />
              ) : (
                <BuildingIcon className="w-7 h-7 text-primary" />
              )}
            </div>
            <div className="pb-1 flex-1 min-w-0">
              <h2 className="font-bold text-lg leading-tight truncate">{company.name}</h2>
              {company.description && (
                <p className="text-xs text-muted-foreground line-clamp-1">{company.description}</p>
              )}
            </div>
            <Button size="sm" variant="secondary" asChild className="shrink-0 cursor-pointer">
              <Link to={`/${lng}/owner/company`}>{t("buttons.edit", { ns: "common" })}</Link>
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Quick Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {stats.map(({ labelKey, icon: Icon, value, toSuffix, color }, i) => (
          <motion.div
            key={labelKey}
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.3, delay: 0.1 + i * 0.05, ease: "easeOut" }}
          >
            <Link to={`/${lng}${toSuffix}`}>
              <Card className="p-4 hover:border-primary/40 hover:shadow-md transition-all cursor-pointer group">
                <div className="w-9 h-9 rounded-lg bg-muted flex items-center justify-center mb-2 group-hover:bg-primary/10 transition-colors">
                  <Icon className={cn("w-4.5 h-4.5", color)} />
                </div>
                <div className="text-2xl font-bold">{value}</div>
                <div className="text-xs text-muted-foreground">{t(labelKey)}</div>
                <ArrowRightIcon className="w-3 h-3 text-muted-foreground mt-2 group-hover:text-primary group-hover:translate-x-0.5 transition-all" />
              </Card>
            </Link>
          </motion.div>
        ))}
      </div>

      {/* Commission Overview */}
      {commissions && commissions.rate > 0 && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base flex items-center gap-2">
              <PercentIcon className="w-4 h-4" /> Commissions
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-3 gap-3">
              <div className="rounded-lg bg-muted p-3 text-center">
                <div className="text-xs text-muted-foreground mb-1">Rate</div>
                <div className="font-bold text-lg">{commissions.rate}%</div>
                <Badge variant="secondary" className="text-[10px] mt-1">
                  {commissions.paidBy === "company" ? "Company pays" : "Traveler pays"}
                </Badge>
              </div>
              <div className="rounded-lg bg-orange-50 dark:bg-orange-950/30 p-3 text-center">
                <div className="text-xs text-muted-foreground mb-1">Pending</div>
                <div className="font-bold text-lg text-orange-600">{commissions.pendingTotal.toLocaleString()}</div>
                <div className="text-[10px] text-muted-foreground">{commissions.currency}</div>
              </div>
              <div className="rounded-lg bg-green-50 dark:bg-green-950/30 p-3 text-center">
                <div className="text-xs text-muted-foreground mb-1">Paid</div>
                <div className="font-bold text-lg text-green-600">{commissions.paidTotal.toLocaleString()}</div>
                <div className="text-[10px] text-muted-foreground">{commissions.currency}</div>
              </div>
            </div>
            {commissions.entries.length > 0 && (
              <div className="space-y-1 max-h-48 overflow-y-auto">
                {commissions.entries.slice(0, 5).map((e) => (
                  <div key={e._id} className="flex items-center gap-2 p-2 rounded-lg text-xs hover:bg-muted/50">
                    <span className="flex-1 truncate">{e.passengerName} — {e.bookingRef}</span>
                    <span className="font-semibold">{e.amount.toLocaleString()} {e.currency}</span>
                    <Badge variant={e.status === "paid" ? "default" : "secondary"} className="text-[9px]">{e.status}</Badge>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  );
}
