import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { PencilIcon } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { cn } from "@/lib/utils.ts";
import { errorMessage } from "@/lib/utils";
import {
  getAllLandingContentSupabase,
  getLandingLiveStatsSupabase,
  upsertLandingContentSupabase,
  type LandingContentMap,
  type LandingLiveStats,
} from "@/lib/supabase/landing-content.ts";
import { recordPlatformAuditSupabase } from "@/lib/supabase/platform-audit-log.ts";
import {
  SECTION_META,
  StatBadge,
  HeroEditor,
  StatsEditor,
  FeaturesEditor,
  TestimonialsEditor,
  TrustSignalsEditor,
  HowItWorksEditor,
  CtaEditor,
  type SectionId,
} from "./landing-cms-editors.tsx";

// CMS "Landing Page" — variante Supabase (prod). Remplace le placeholder
// "ComingSoon" affiché depuis la migration Convex -> Supabase (voir
// migration 161_landing_content_supabase). Les éditeurs de section sont
// partagés avec la variante Convex legacy (landing-cms-editors.tsx).

const SECTION_LABELS: Record<SectionId, string> = {
  hero: "Hero",
  stats: "Stats",
  features_travelers: "Traveler features",
  features_companies: "Company features",
  testimonials: "Testimonials",
  trust_signals: "Trust signals",
  how_it_works: "How it works",
  cta: "Call to action",
};

export default function SupabaseLandingCmsTab() {
  const { t } = useTranslation("admin");
  const [cmsData, setCmsData] = useState<LandingContentMap | undefined>(undefined);
  const [liveStats, setLiveStats] = useState<LandingLiveStats | undefined>(undefined);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [activeSection, setActiveSection] = useState<SectionId>("hero");
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    setLoadError(null);
    try {
      const [content, stats] = await Promise.all([
        getAllLandingContentSupabase(),
        getLandingLiveStatsSupabase(),
      ]);
      setCmsData(content);
      setLiveStats(stats);
    } catch (err) {
      setLoadError(errorMessage(err, t("cms.load_error", { defaultValue: "Failed to load" })));
      setCmsData({});
      setLiveStats({ companies: 0, trips: 0, travelers: 0, cities: 0 });
    }
  }, [t]);

  useEffect(() => {
    void load();
  }, [load]);

  if (cmsData === undefined || liveStats === undefined) {
    return (
      <div className="space-y-4">
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-24 w-full rounded-xl" />
        ))}
      </div>
    );
  }

  const handleSave = async (section: SectionId, content: string) => {
    setSaving(true);
    try {
      await upsertLandingContentSupabase(section, content);
      setCmsData((prev) => ({ ...(prev ?? {}), [section]: content }));
      toast.success(t("cms.saved", { defaultValue: "Section saved" }));
      void recordPlatformAuditSupabase({
        moduleKey: "admin.landing",
        action: "update",
        summary: `Section landing « ${SECTION_LABELS[section]} » mise à jour`,
      });
    } catch (err) {
      toast.error(errorMessage(err, t("cms.save_error", { defaultValue: "Failed to save" })));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <PencilIcon className="w-4 h-4" />
          {t("cms.title", { defaultValue: "Landing Page Content" })}
        </CardTitle>
        <p className="text-xs text-muted-foreground">
          {t("cms.desc", { defaultValue: "Edit content displayed on the public landing page. Stats are auto-calculated from your data." })}
        </p>
        {loadError && (
          <p className="text-xs text-destructive">{loadError}</p>
        )}
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Live Stats Preview */}
        <div className="p-3 rounded-xl bg-primary/5 border border-primary/10">
          <div className="text-xs font-semibold text-primary mb-2">
            {t("cms.live_stats", { defaultValue: "Live Stats (auto-calculated)" })}
          </div>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <StatBadge label={t("cms.stat_companies", { defaultValue: "Companies" })} value={liveStats.companies} />
            <StatBadge label={t("cms.stat_trips", { defaultValue: "Trips completed" })} value={liveStats.trips} />
            <StatBadge label={t("cms.stat_travelers", { defaultValue: "Travelers" })} value={liveStats.travelers} />
            <StatBadge label={t("cms.stat_cities", { defaultValue: "Cities" })} value={liveStats.cities} />
          </div>
        </div>

        {/* Section Tabs */}
        <div className="flex flex-wrap gap-1.5">
          {SECTION_META.map(({ id, labelKey, icon: Icon }) => (
            <button
              key={id}
              onClick={() => setActiveSection(id)}
              className={cn(
                "flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors cursor-pointer",
                activeSection === id
                  ? "bg-primary text-primary-foreground"
                  : "bg-muted text-muted-foreground hover:text-foreground",
              )}
            >
              <Icon className="w-3 h-3" />
              {t(labelKey, { defaultValue: id.replace(/_/g, " ") })}
            </button>
          ))}
        </div>

        {/* Active section editor */}
        {activeSection === "hero" && (
          <HeroEditor
            initial={cmsData.hero}
            onSave={(c) => void handleSave("hero", c)}
            saving={saving}
          />
        )}
        {activeSection === "stats" && (
          <StatsEditor
            initial={cmsData.stats}
            liveStats={liveStats}
            onSave={(c) => void handleSave("stats", c)}
            saving={saving}
          />
        )}
        {activeSection === "features_travelers" && (
          <FeaturesEditor
            initial={cmsData.features_travelers}
            sectionLabel={t("cms.features_travelers", { defaultValue: "Traveler Features" })}
            onSave={(c) => void handleSave("features_travelers", c)}
            saving={saving}
          />
        )}
        {activeSection === "features_companies" && (
          <FeaturesEditor
            initial={cmsData.features_companies}
            sectionLabel={t("cms.features_companies", { defaultValue: "Company Features" })}
            onSave={(c) => void handleSave("features_companies", c)}
            saving={saving}
          />
        )}
        {activeSection === "testimonials" && (
          <TestimonialsEditor
            initial={cmsData.testimonials}
            onSave={(c) => void handleSave("testimonials", c)}
            saving={saving}
          />
        )}
        {activeSection === "trust_signals" && (
          <TrustSignalsEditor
            initial={cmsData.trust_signals}
            onSave={(c) => void handleSave("trust_signals", c)}
            saving={saving}
          />
        )}
        {activeSection === "how_it_works" && (
          <HowItWorksEditor
            initial={cmsData.how_it_works}
            onSave={(c) => void handleSave("how_it_works", c)}
            saving={saving}
          />
        )}
        {activeSection === "cta" && (
          <CtaEditor
            initial={cmsData.cta}
            onSave={(c) => void handleSave("cta", c)}
            saving={saving}
          />
        )}
      </CardContent>
    </Card>
  );
}
