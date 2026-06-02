import { useState, useEffect } from "react";
import { useQuery, useMutation } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import {
  PencilIcon,
  SaveIcon,
  RotateCcwIcon,
  StarIcon,
  GlobeIcon,
  ZapIcon,
  MessageSquareIcon,
  ShieldCheckIcon,
  LayoutDashboardIcon,
  XIcon,
  PlusIcon,
  Trash2Icon,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { cn } from "@/lib/utils.ts";

// ─── Types for content sections ──────────────────────────────────────────────

type HeroContent = {
  badge: string;
  title: string;
  description: string;
  ctaSearch: string;
  ctaRegister: string;
  heroCardTitle: string;
  heroCardDesc: string;
};

type StatsOverrides = {
  useAutoStats: boolean;
  overrides: { label: string; value: string }[];
};

type FeatureItem = {
  title: string;
  desc: string;
};

type TestimonialItem = {
  name: string;
  role: string;
  text: string;
  rating: number;
  city: string;
};

type TrustSignalItem = {
  text: string;
};

type HowStep = {
  step: string;
  title: string;
  desc: string;
};

type CtaContent = {
  title: string;
  description: string;
  ctaButton: string;
};

// ─── Section editor types ────────────────────────────────────────────────────

type SectionId = "hero" | "stats" | "features_travelers" | "features_companies" | "testimonials" | "trust_signals" | "how_it_works" | "cta";

const SECTION_META: { id: SectionId; labelKey: string; icon: typeof StarIcon }[] = [
  { id: "hero", labelKey: "cms.hero", icon: ZapIcon },
  { id: "stats", labelKey: "cms.stats", icon: LayoutDashboardIcon },
  { id: "features_travelers", labelKey: "cms.features_travelers", icon: StarIcon },
  { id: "features_companies", labelKey: "cms.features_companies", icon: GlobeIcon },
  { id: "testimonials", labelKey: "cms.testimonials", icon: MessageSquareIcon },
  { id: "trust_signals", labelKey: "cms.trust_signals", icon: ShieldCheckIcon },
  { id: "how_it_works", labelKey: "cms.how_it_works", icon: LayoutDashboardIcon },
  { id: "cta", labelKey: "cms.cta", icon: ZapIcon },
];

// ─── Main Component ──────────────────────────────────────────────────────────

export default function LandingCmsTab() {
  const { t } = useTranslation("admin");
  const cmsData = useQuery(api.landingContent.getAll, {});
  const liveStats = useQuery(api.landingContent.getLiveStats, {});
  const updateSection = useMutation(api.landingContent.updateSection);

  const [activeSection, setActiveSection] = useState<SectionId>("hero");
  const [saving, setSaving] = useState(false);

  if (cmsData === undefined || liveStats === undefined) {
    return (
      <div className="space-y-4">
        {Array.from({ length: 3 }).map((_, i) => (
          <Skeleton key={i} className="h-24 w-full rounded-xl" />
        ))}
      </div>
    );
  }

  const handleSave = async (section: string, content: string) => {
    setSaving(true);
    try {
      await updateSection({ section, content });
      toast.success(t("cms.saved", { defaultValue: "Section saved" }));
    } catch {
      toast.error(t("cms.save_error", { defaultValue: "Failed to save" }));
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
            onSave={(c) => handleSave("hero", c)}
            saving={saving}
          />
        )}
        {activeSection === "stats" && (
          <StatsEditor
            initial={cmsData.stats}
            liveStats={liveStats}
            onSave={(c) => handleSave("stats", c)}
            saving={saving}
          />
        )}
        {activeSection === "features_travelers" && (
          <FeaturesEditor
            initial={cmsData.features_travelers}
            sectionLabel={t("cms.features_travelers", { defaultValue: "Traveler Features" })}
            onSave={(c) => handleSave("features_travelers", c)}
            saving={saving}
          />
        )}
        {activeSection === "features_companies" && (
          <FeaturesEditor
            initial={cmsData.features_companies}
            sectionLabel={t("cms.features_companies", { defaultValue: "Company Features" })}
            onSave={(c) => handleSave("features_companies", c)}
            saving={saving}
          />
        )}
        {activeSection === "testimonials" && (
          <TestimonialsEditor
            initial={cmsData.testimonials}
            onSave={(c) => handleSave("testimonials", c)}
            saving={saving}
          />
        )}
        {activeSection === "trust_signals" && (
          <TrustSignalsEditor
            initial={cmsData.trust_signals}
            onSave={(c) => handleSave("trust_signals", c)}
            saving={saving}
          />
        )}
        {activeSection === "how_it_works" && (
          <HowItWorksEditor
            initial={cmsData.how_it_works}
            onSave={(c) => handleSave("how_it_works", c)}
            saving={saving}
          />
        )}
        {activeSection === "cta" && (
          <CtaEditor
            initial={cmsData.cta}
            onSave={(c) => handleSave("cta", c)}
            saving={saving}
          />
        )}
      </CardContent>
    </Card>
  );
}

// ─── Helper components ───────────────────────────────────────────────────────

function StatBadge({ label, value }: { label: string; value: number }) {
  return (
    <div className="text-center p-2 rounded-lg bg-background border">
      <div className="text-lg font-bold text-primary">{value}</div>
      <div className="text-[10px] text-muted-foreground">{label}</div>
    </div>
  );
}

function SaveBar({ onSave, onReset, saving, dirty }: { onSave: () => void; onReset: () => void; saving: boolean; dirty: boolean }) {
  return (
    <div className="flex items-center gap-2 pt-3 border-t">
      <Button size="sm" onClick={onSave} disabled={saving || !dirty} className="cursor-pointer gap-1.5">
        <SaveIcon className="w-3 h-3" />
        {saving ? "Saving..." : "Save"}
      </Button>
      <Button size="sm" variant="ghost" onClick={onReset} disabled={saving} className="cursor-pointer gap-1.5">
        <RotateCcwIcon className="w-3 h-3" />
        Reset
      </Button>
      {dirty && <Badge className="text-[10px] bg-amber-500/10 text-amber-600 border-amber-500/30">Unsaved changes</Badge>}
    </div>
  );
}

// ─── Hero Editor ─────────────────────────────────────────────────────────────

function HeroEditor({ initial, onSave, saving }: { initial?: string; onSave: (c: string) => void; saving: boolean }) {
  const { t } = useTranslation("admin");
  const defaults: HeroContent = {
    badge: "Bus travel made simple",
    title: "Book Your Bus Ticket in Seconds",
    description: "Search routes, compare prices, and book seats instantly. Travel across West Africa with confidence.",
    ctaSearch: "Search Trips",
    ctaRegister: "Register Your Company",
    heroCardTitle: "Abidjan → Yamoussoukro",
    heroCardDesc: "15 seats available · 5,000 XAF",
  };
  const parsed: HeroContent = initial ? JSON.parse(initial) : defaults;
  const [form, setForm] = useState(parsed);
  const [dirty, setDirty] = useState(false);

  useEffect(() => {
    if (initial) {
      setForm(JSON.parse(initial));
      setDirty(false);
    }
  }, [initial]);

  const update = (field: keyof HeroContent, val: string) => {
    setForm((p) => ({ ...p, [field]: val }));
    setDirty(true);
  };

  return (
    <div className="space-y-3">
      <h3 className="text-sm font-semibold">{t("cms.hero", { defaultValue: "Hero Section" })}</h3>
      <div className="grid gap-3 sm:grid-cols-2">
        <div>
          <label className="text-xs text-muted-foreground">Badge text</label>
          <Input value={form.badge} onChange={(e) => update("badge", e.target.value)} />
        </div>
        <div>
          <label className="text-xs text-muted-foreground">CTA Search button</label>
          <Input value={form.ctaSearch} onChange={(e) => update("ctaSearch", e.target.value)} />
        </div>
      </div>
      <div>
        <label className="text-xs text-muted-foreground">Title</label>
        <Input value={form.title} onChange={(e) => update("title", e.target.value)} />
      </div>
      <div>
        <label className="text-xs text-muted-foreground">Description</label>
        <Textarea value={form.description} onChange={(e) => update("description", e.target.value)} rows={3} />
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <div>
          <label className="text-xs text-muted-foreground">CTA Register button</label>
          <Input value={form.ctaRegister} onChange={(e) => update("ctaRegister", e.target.value)} />
        </div>
        <div>
          <label className="text-xs text-muted-foreground">Hero card title</label>
          <Input value={form.heroCardTitle} onChange={(e) => update("heroCardTitle", e.target.value)} />
        </div>
      </div>
      <div>
        <label className="text-xs text-muted-foreground">Hero card description</label>
        <Input value={form.heroCardDesc} onChange={(e) => update("heroCardDesc", e.target.value)} />
      </div>
      <SaveBar
        onSave={() => onSave(JSON.stringify(form))}
        onReset={() => { setForm(parsed); setDirty(false); }}
        saving={saving}
        dirty={dirty}
      />
    </div>
  );
}

// ─── Stats Editor ────────────────────────────────────────────────────────────

function StatsEditor({ initial, liveStats, onSave, saving }: { initial?: string; liveStats: { companies: number; trips: number; travelers: number; cities: number }; onSave: (c: string) => void; saving: boolean }) {
  const { t } = useTranslation("admin");
  const defaults: StatsOverrides = {
    useAutoStats: true,
    overrides: [
      { label: "Trips completed", value: "" },
      { label: "Bus companies", value: "" },
      { label: "Happy travelers", value: "" },
      { label: "Cities connected", value: "" },
    ],
  };
  const parsed: StatsOverrides = initial ? JSON.parse(initial) : defaults;
  const [form, setForm] = useState(parsed);
  const [dirty, setDirty] = useState(false);

  useEffect(() => {
    if (initial) {
      setForm(JSON.parse(initial));
      setDirty(false);
    }
  }, [initial]);

  const toggleAuto = () => {
    setForm((p) => ({ ...p, useAutoStats: !p.useAutoStats }));
    setDirty(true);
  };

  const updateOverride = (idx: number, field: "label" | "value", val: string) => {
    setForm((p) => {
      const items = [...p.overrides];
      items[idx] = { ...items[idx], [field]: val };
      return { ...p, overrides: items };
    });
    setDirty(true);
  };

  return (
    <div className="space-y-3">
      <h3 className="text-sm font-semibold">{t("cms.stats", { defaultValue: "Stats Section" })}</h3>
      <div className="flex items-center gap-3">
        <button
          onClick={toggleAuto}
          className={cn(
            "px-3 py-1.5 rounded-lg text-xs font-medium cursor-pointer transition-colors",
            form.useAutoStats ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground",
          )}
        >
          Auto-calculated
        </button>
        <button
          onClick={toggleAuto}
          className={cn(
            "px-3 py-1.5 rounded-lg text-xs font-medium cursor-pointer transition-colors",
            !form.useAutoStats ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground",
          )}
        >
          Manual overrides
        </button>
      </div>

      {form.useAutoStats ? (
        <div className="p-3 rounded-lg bg-muted/50 text-xs text-muted-foreground">
          Stats will be calculated from real data: <strong>{liveStats.trips}</strong> trips, <strong>{liveStats.companies}</strong> companies, <strong>{liveStats.travelers}</strong> travelers, <strong>{liveStats.cities}</strong> cities.
        </div>
      ) : (
        <div className="space-y-2">
          <p className="text-xs text-muted-foreground">Override displayed values (leave value empty to use auto):</p>
          {form.overrides.map((item, idx) => (
            <div key={idx} className="grid grid-cols-2 gap-2">
              <Input
                placeholder="Label"
                value={item.label}
                onChange={(e) => updateOverride(idx, "label", e.target.value)}
              />
              <Input
                placeholder={`Auto value or e.g. "500+"`}
                value={item.value}
                onChange={(e) => updateOverride(idx, "value", e.target.value)}
              />
            </div>
          ))}
        </div>
      )}
      <SaveBar
        onSave={() => onSave(JSON.stringify(form))}
        onReset={() => { setForm(parsed); setDirty(false); }}
        saving={saving}
        dirty={dirty}
      />
    </div>
  );
}

// ─── Features Editor (reusable for travelers / companies) ────────────────────

function FeaturesEditor({ initial, sectionLabel, onSave, saving }: { initial?: string; sectionLabel: string; onSave: (c: string) => void; saving: boolean }) {
  const defaults: FeatureItem[] = [
    { title: "Feature title", desc: "Feature description" },
  ];
  const parsed: FeatureItem[] = initial ? JSON.parse(initial) : defaults;
  const [items, setItems] = useState(parsed);
  const [dirty, setDirty] = useState(false);

  useEffect(() => {
    if (initial) {
      setItems(JSON.parse(initial));
      setDirty(false);
    }
  }, [initial]);

  const updateItem = (idx: number, field: keyof FeatureItem, val: string) => {
    setItems((p) => {
      const arr = [...p];
      arr[idx] = { ...arr[idx], [field]: val };
      return arr;
    });
    setDirty(true);
  };

  const addItem = () => {
    setItems((p) => [...p, { title: "", desc: "" }]);
    setDirty(true);
  };

  const removeItem = (idx: number) => {
    setItems((p) => p.filter((_, i) => i !== idx));
    setDirty(true);
  };

  return (
    <div className="space-y-3">
      <h3 className="text-sm font-semibold">{sectionLabel}</h3>
      {items.map((item, idx) => (
        <div key={idx} className="p-3 rounded-lg border space-y-2 relative">
          <button
            onClick={() => removeItem(idx)}
            className="absolute top-2 right-2 text-muted-foreground hover:text-destructive cursor-pointer"
          >
            <XIcon className="w-3.5 h-3.5" />
          </button>
          <Input
            placeholder="Title"
            value={item.title}
            onChange={(e) => updateItem(idx, "title", e.target.value)}
          />
          <Textarea
            placeholder="Description"
            value={item.desc}
            onChange={(e) => updateItem(idx, "desc", e.target.value)}
            rows={2}
          />
        </div>
      ))}
      <Button size="sm" variant="secondary" className="cursor-pointer gap-1.5" onClick={addItem}>
        <PlusIcon className="w-3 h-3" /> Add feature
      </Button>
      <SaveBar
        onSave={() => onSave(JSON.stringify(items))}
        onReset={() => { setItems(parsed); setDirty(false); }}
        saving={saving}
        dirty={dirty}
      />
    </div>
  );
}

// ─── Testimonials Editor ─────────────────────────────────────────────────────

function TestimonialsEditor({ initial, onSave, saving }: { initial?: string; onSave: (c: string) => void; saving: boolean }) {
  const { t } = useTranslation("admin");
  const defaults: TestimonialItem[] = [
    { name: "Aminata K.", role: "Frequent traveler", text: "Great experience!", rating: 5, city: "Abidjan" },
  ];
  const parsed: TestimonialItem[] = initial ? JSON.parse(initial) : defaults;
  const [items, setItems] = useState(parsed);
  const [dirty, setDirty] = useState(false);

  useEffect(() => {
    if (initial) {
      setItems(JSON.parse(initial));
      setDirty(false);
    }
  }, [initial]);

  const updateItem = (idx: number, field: keyof TestimonialItem, val: string | number) => {
    setItems((p) => {
      const arr = [...p];
      arr[idx] = { ...arr[idx], [field]: val };
      return arr;
    });
    setDirty(true);
  };

  const addItem = () => {
    setItems((p) => [...p, { name: "", role: "", text: "", rating: 5, city: "" }]);
    setDirty(true);
  };

  const removeItem = (idx: number) => {
    setItems((p) => p.filter((_, i) => i !== idx));
    setDirty(true);
  };

  return (
    <div className="space-y-3">
      <h3 className="text-sm font-semibold">{t("cms.testimonials", { defaultValue: "Testimonials" })}</h3>
      {items.map((item, idx) => (
        <div key={idx} className="p-3 rounded-lg border space-y-2 relative">
          <button
            onClick={() => removeItem(idx)}
            className="absolute top-2 right-2 text-muted-foreground hover:text-destructive cursor-pointer"
          >
            <XIcon className="w-3.5 h-3.5" />
          </button>
          <div className="grid grid-cols-2 gap-2">
            <Input placeholder="Name" value={item.name} onChange={(e) => updateItem(idx, "name", e.target.value)} />
            <Input placeholder="City" value={item.city} onChange={(e) => updateItem(idx, "city", e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-2">
            <Input placeholder="Role (e.g. Student)" value={item.role} onChange={(e) => updateItem(idx, "role", e.target.value)} />
            <Input
              type="number"
              min={1}
              max={5}
              placeholder="Rating (1-5)"
              value={item.rating}
              onChange={(e) => updateItem(idx, "rating", parseInt(e.target.value) || 5)}
            />
          </div>
          <Textarea
            placeholder="Testimonial text"
            value={item.text}
            onChange={(e) => updateItem(idx, "text", e.target.value)}
            rows={2}
          />
        </div>
      ))}
      <Button size="sm" variant="secondary" className="cursor-pointer gap-1.5" onClick={addItem}>
        <PlusIcon className="w-3 h-3" /> Add testimonial
      </Button>
      <SaveBar
        onSave={() => onSave(JSON.stringify(items))}
        onReset={() => { setItems(parsed); setDirty(false); }}
        saving={saving}
        dirty={dirty}
      />
    </div>
  );
}

// ─── Trust Signals Editor ────────────────────────────────────────────────────

function TrustSignalsEditor({ initial, onSave, saving }: { initial?: string; onSave: (c: string) => void; saving: boolean }) {
  const { t } = useTranslation("admin");
  const defaults: TrustSignalItem[] = [
    { text: "Verified bus companies only" },
    { text: "Secure mobile money payments" },
    { text: "24/7 customer support via WhatsApp" },
    { text: "Digital tickets with QR verification" },
  ];
  const parsed: TrustSignalItem[] = initial ? JSON.parse(initial) : defaults;
  const [items, setItems] = useState(parsed);
  const [dirty, setDirty] = useState(false);

  useEffect(() => {
    if (initial) {
      setItems(JSON.parse(initial));
      setDirty(false);
    }
  }, [initial]);

  const updateItem = (idx: number, val: string) => {
    setItems((p) => {
      const arr = [...p];
      arr[idx] = { text: val };
      return arr;
    });
    setDirty(true);
  };

  const addItem = () => {
    setItems((p) => [...p, { text: "" }]);
    setDirty(true);
  };

  const removeItem = (idx: number) => {
    setItems((p) => p.filter((_, i) => i !== idx));
    setDirty(true);
  };

  return (
    <div className="space-y-3">
      <h3 className="text-sm font-semibold">{t("cms.trust_signals", { defaultValue: "Trust Signals" })}</h3>
      {items.map((item, idx) => (
        <div key={idx} className="flex items-center gap-2">
          <Input value={item.text} onChange={(e) => updateItem(idx, e.target.value)} placeholder="Trust signal text" className="flex-1" />
          <button onClick={() => removeItem(idx)} className="text-muted-foreground hover:text-destructive cursor-pointer">
            <Trash2Icon className="w-3.5 h-3.5" />
          </button>
        </div>
      ))}
      <Button size="sm" variant="secondary" className="cursor-pointer gap-1.5" onClick={addItem}>
        <PlusIcon className="w-3 h-3" /> Add signal
      </Button>
      <SaveBar
        onSave={() => onSave(JSON.stringify(items))}
        onReset={() => { setItems(parsed); setDirty(false); }}
        saving={saving}
        dirty={dirty}
      />
    </div>
  );
}

// ─── How It Works Editor ─────────────────────────────────────────────────────

function HowItWorksEditor({ initial, onSave, saving }: { initial?: string; onSave: (c: string) => void; saving: boolean }) {
  const { t } = useTranslation("admin");
  const defaults: HowStep[] = [
    { step: "1", title: "Search", desc: "Enter your origin, destination, and travel date." },
    { step: "2", title: "Choose", desc: "Compare companies, prices, and departure times." },
    { step: "3", title: "Travel", desc: "Pay securely and receive your digital ticket instantly." },
  ];
  const parsed: HowStep[] = initial ? JSON.parse(initial) : defaults;
  const [items, setItems] = useState(parsed);
  const [dirty, setDirty] = useState(false);

  useEffect(() => {
    if (initial) {
      setItems(JSON.parse(initial));
      setDirty(false);
    }
  }, [initial]);

  const updateItem = (idx: number, field: keyof HowStep, val: string) => {
    setItems((p) => {
      const arr = [...p];
      arr[idx] = { ...arr[idx], [field]: val };
      return arr;
    });
    setDirty(true);
  };

  const addItem = () => {
    setItems((p) => [...p, { step: String(p.length + 1), title: "", desc: "" }]);
    setDirty(true);
  };

  const removeItem = (idx: number) => {
    setItems((p) => p.filter((_, i) => i !== idx));
    setDirty(true);
  };

  return (
    <div className="space-y-3">
      <h3 className="text-sm font-semibold">{t("cms.how_it_works", { defaultValue: "How It Works" })}</h3>
      {items.map((item, idx) => (
        <div key={idx} className="p-3 rounded-lg border space-y-2 relative">
          <button onClick={() => removeItem(idx)} className="absolute top-2 right-2 text-muted-foreground hover:text-destructive cursor-pointer">
            <XIcon className="w-3.5 h-3.5" />
          </button>
          <div className="grid grid-cols-4 gap-2">
            <Input placeholder="Step #" value={item.step} onChange={(e) => updateItem(idx, "step", e.target.value)} />
            <Input placeholder="Title" value={item.title} onChange={(e) => updateItem(idx, "title", e.target.value)} className="col-span-3" />
          </div>
          <Textarea placeholder="Description" value={item.desc} onChange={(e) => updateItem(idx, "desc", e.target.value)} rows={2} />
        </div>
      ))}
      <Button size="sm" variant="secondary" className="cursor-pointer gap-1.5" onClick={addItem}>
        <PlusIcon className="w-3 h-3" /> Add step
      </Button>
      <SaveBar
        onSave={() => onSave(JSON.stringify(items))}
        onReset={() => { setItems(parsed); setDirty(false); }}
        saving={saving}
        dirty={dirty}
      />
    </div>
  );
}

// ─── CTA Editor ──────────────────────────────────────────────────────────────

function CtaEditor({ initial, onSave, saving }: { initial?: string; onSave: (c: string) => void; saving: boolean }) {
  const { t } = useTranslation("admin");
  const defaults: CtaContent = {
    title: "Ready to Travel?",
    description: "Join thousands of travelers who book their bus tickets with Tibus every day.",
    ctaButton: "Book a Ticket",
  };
  const parsed: CtaContent = initial ? JSON.parse(initial) : defaults;
  const [form, setForm] = useState(parsed);
  const [dirty, setDirty] = useState(false);

  useEffect(() => {
    if (initial) {
      setForm(JSON.parse(initial));
      setDirty(false);
    }
  }, [initial]);

  const update = (field: keyof CtaContent, val: string) => {
    setForm((p) => ({ ...p, [field]: val }));
    setDirty(true);
  };

  return (
    <div className="space-y-3">
      <h3 className="text-sm font-semibold">{t("cms.cta", { defaultValue: "Call to Action" })}</h3>
      <div>
        <label className="text-xs text-muted-foreground">Title</label>
        <Input value={form.title} onChange={(e) => update("title", e.target.value)} />
      </div>
      <div>
        <label className="text-xs text-muted-foreground">Description</label>
        <Textarea value={form.description} onChange={(e) => update("description", e.target.value)} rows={2} />
      </div>
      <div>
        <label className="text-xs text-muted-foreground">Button text</label>
        <Input value={form.ctaButton} onChange={(e) => update("ctaButton", e.target.value)} />
      </div>
      <SaveBar
        onSave={() => onSave(JSON.stringify(form))}
        onReset={() => { setForm(parsed); setDirty(false); }}
        saving={saving}
        dirty={dirty}
      />
    </div>
  );
}
