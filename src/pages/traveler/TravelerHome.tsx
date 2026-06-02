import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { Link, useParams } from "react-router-dom";
import { BuildingIcon, SearchIcon, ArrowRightIcon, TicketIcon } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Empty, EmptyHeader, EmptyMedia, EmptyTitle, EmptyDescription } from "@/components/ui/empty.tsx";
import { useState } from "react";
import { useTranslation } from "react-i18next";

export default function TravelerHome() {
  const { t } = useTranslation("traveler");
  const { lng } = useParams<{ lng: string }>();
  const user = useQuery(api.users.getCurrentUser, {});
  const companies = useQuery(api.companies.listActiveCompanies, {});
  const [search, setSearch] = useState("");

  const filtered = companies
    ? companies.filter((c) =>
        c.name.toLowerCase().includes(search.toLowerCase()) ||
        c.description?.toLowerCase().includes(search.toLowerCase())
      )
    : [];

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-extrabold tracking-tight">
          {user?.name ? t("greeting", { name: user.name.split(" ")[0] }) + " 👋" : t("find_bus")}
        </h1>
        <p className="text-muted-foreground text-sm mt-1">{t("browse_desc")}</p>
      </div>

      {/* Search */}
      <div className="relative">
        <SearchIcon className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
        <Input
          placeholder={t("search_companies")}
          className="pl-9"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>

      {/* Companies */}
      <div className="space-y-2">
        <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider">{t("companies")}</h2>

        {companies === undefined ? (
          <div className="space-y-3">
            {Array.from({ length: 3 }).map((_, i) => (
              <Skeleton key={i} className="h-20 w-full rounded-xl" />
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <Empty>
            <EmptyHeader>
              <EmptyMedia variant="icon"><BuildingIcon /></EmptyMedia>
              <EmptyTitle>{t("no_companies")}</EmptyTitle>
              <EmptyDescription>
                {search ? t("no_companies_search") : t("no_companies_yet")}
              </EmptyDescription>
            </EmptyHeader>
          </Empty>
        ) : (
          <div className="space-y-3">
            {filtered.map((company) => (
              <Link key={company._id} to={`/${lng}/company/${company._id}`}>
                <Card className="hover:border-primary/40 transition-all cursor-pointer">
                  <CardContent className="p-4 flex items-center gap-4">
                    <div className="w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center shrink-0 overflow-hidden">
                      {company.logoUrl ? (
                        <img src={company.logoUrl} alt={company.name} className="w-full h-full object-cover" />
                      ) : (
                        <BuildingIcon className="w-5 h-5 text-primary" />
                      )}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="font-semibold text-sm truncate">{company.name}</span>
                        {company.planId && (
                          <Badge variant="secondary" className="text-[9px] h-4 px-1.5 shrink-0">
                            {company.planId.toUpperCase()}
                          </Badge>
                        )}
                      </div>
                      {company.description ? (
                        <p className="text-xs text-muted-foreground line-clamp-1 mt-0.5">{company.description}</p>
                      ) : (
                        <p className="text-xs text-muted-foreground mt-0.5">{t("view_trips")}</p>
                      )}
                    </div>
                    <ArrowRightIcon className="w-4 h-4 text-muted-foreground shrink-0" />
                  </CardContent>
                </Card>
              </Link>
            ))}
          </div>
        )}
      </div>

      {/* Search trips shortcut */}
      <Link to={`/${lng}/traveler/search`}>
        <div className="p-4 rounded-xl bg-primary text-primary-foreground flex items-center justify-between cursor-pointer hover:opacity-90 transition-opacity">
          <div className="flex items-center gap-3">
            <SearchIcon className="w-5 h-5" />
            <div>
              <p className="text-sm font-semibold">{t("search_all_trips")}</p>
              <p className="text-xs opacity-80">{t("search_all_trips_desc")}</p>
            </div>
          </div>
          <ArrowRightIcon className="w-4 h-4" />
        </div>
      </Link>

      {/* My Bookings shortcut */}
      <div className="p-4 rounded-xl border border-dashed border-border flex items-center justify-between">
        <div className="flex items-center gap-3">
          <TicketIcon className="w-5 h-5 text-primary" />
          <div>
            <p className="text-sm font-semibold">{t("my_bookings")}</p>
            <p className="text-xs text-muted-foreground">{t("my_bookings_desc")}</p>
          </div>
        </div>
        <Link to={`/${lng}/traveler/bookings`} className="text-xs font-medium text-primary hover:underline">
          {t("buttons.view_all", { ns: "common" })}
        </Link>
      </div>
    </div>
  );
}
