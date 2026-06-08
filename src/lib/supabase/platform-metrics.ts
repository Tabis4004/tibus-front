import { supabase } from "@/lib/supabase";

export type ScalingTierId =
  | "demarrage"
  | "croissance"
  | "fort_trafic"
  | "national"
  | "tres_haut_volume";

export type PlatformScalingMetrics = {
  generatedAt: string;
  supabaseProjectRef: string;
  usersTotal: number;
  companiesTotal: number;
  companiesActive: number;
  countriesTotal: number;
  citiesTotal: number;
  sellersTotal: number;
  ownersTotal: number;
  travelersTotal: number;
  ticketsToday: number;
  tickets7d: number;
  tickets30d: number;
  avgTicketsPerDay30d: number;
  estimatedPeakConnections: number;
  databaseSizeBytes: number | null;
  recommendedTier: ScalingTierId;
  upcomingTrips7d: number;
};

export type ScalingTierRow = {
  id: ScalingTierId;
  labelKey: string;
  sellersRange: string;
  reservationsPerDay: string;
  connectionsPeak: string;
  recommendationKey: string;
  costRange: string;
};

export const SCALING_TIER_ROWS: ScalingTierRow[] = [
  {
    id: "demarrage",
    labelKey: "scaling_metrics.tiers.demarrage",
    sellersRange: "5 – 20",
    reservationsPerDay: "100 – 500",
    connectionsPeak: "< 30",
    recommendationKey: "scaling_metrics.reco.demarrage",
    costRange: "0 – 35 €",
  },
  {
    id: "croissance",
    labelKey: "scaling_metrics.tiers.croissance",
    sellersRange: "30 – 100",
    reservationsPerDay: "500 – 3 000",
    connectionsPeak: "30 – 80",
    recommendationKey: "scaling_metrics.reco.croissance",
    costRange: "35 – 90 €",
  },
  {
    id: "fort_trafic",
    labelKey: "scaling_metrics.tiers.fort_trafic",
    sellersRange: "100 – 300",
    reservationsPerDay: "3 000 – 15 000",
    connectionsPeak: "80 – 200",
    recommendationKey: "scaling_metrics.reco.fort_trafic",
    costRange: "90 – 250 €",
  },
  {
    id: "national",
    labelKey: "scaling_metrics.tiers.national",
    sellersRange: "300 – 800",
    reservationsPerDay: "15 000 – 50 000",
    connectionsPeak: "200 – 600",
    recommendationKey: "scaling_metrics.reco.national",
    costRange: "150 – 450 €",
  },
  {
    id: "tres_haut_volume",
    labelKey: "scaling_metrics.tiers.tres_haut_volume",
    sellersRange: "800+",
    reservationsPerDay: "50 000+",
    connectionsPeak: "600+",
    recommendationKey: "scaling_metrics.reco.tres_haut_volume",
    costRange: "300 – 800 €",
  },
];

function num(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

function tierId(value: unknown): ScalingTierId {
  const allowed: ScalingTierId[] = [
    "demarrage",
    "croissance",
    "fort_trafic",
    "national",
    "tres_haut_volume",
  ];
  if (typeof value === "string" && allowed.includes(value as ScalingTierId)) {
    return value as ScalingTierId;
  }
  return "demarrage";
}

function normalizeMetrics(data: unknown): PlatformScalingMetrics {
  const row = (data ?? {}) as Record<string, unknown>;
  return {
    generatedAt: String(row.generatedAt ?? new Date().toISOString()),
    supabaseProjectRef: String(row.supabaseProjectRef ?? "kqudaqtydimjclwaihqr"),
    usersTotal: num(row.usersTotal),
    companiesTotal: num(row.companiesTotal),
    companiesActive: num(row.companiesActive),
    countriesTotal: num(row.countriesTotal),
    citiesTotal: num(row.citiesTotal),
    sellersTotal: num(row.sellersTotal),
    ownersTotal: num(row.ownersTotal),
    travelersTotal: num(row.travelersTotal),
    ticketsToday: num(row.ticketsToday),
    tickets7d: num(row.tickets7d),
    tickets30d: num(row.tickets30d),
    avgTicketsPerDay30d: num(row.avgTicketsPerDay30d),
    estimatedPeakConnections: num(row.estimatedPeakConnections),
    databaseSizeBytes:
      row.databaseSizeBytes == null ? null : num(row.databaseSizeBytes),
    recommendedTier: tierId(row.recommendedTier),
    upcomingTrips7d: num(row.upcomingTrips7d),
  };
}

export async function getPlatformScalingMetricsSupabase(): Promise<PlatformScalingMetrics> {
  const { data, error } = await supabase.rpc("get_platform_scaling_metrics");
  if (error) throw error;
  return normalizeMetrics(data);
}

export function formatBytes(bytes: number | null): string {
  if (bytes == null || bytes <= 0) return "—";
  const units = ["o", "Ko", "Mo", "Go", "To"];
  let value = bytes;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
}

export function buildMetricsExportPayload(
  metrics: PlatformScalingMetrics,
  tiers = SCALING_TIER_ROWS,
): Record<string, unknown> {
  return {
    exportedAt: new Date().toISOString(),
    metrics,
    decisionGrid: tiers,
    migrationChecklist: {
      phase0: [
        "Documenter secrets Edge Functions (FEDAPAY, push, SMS)",
        "Inventorier migrations SQL exécutées vs repo",
        "Baseline perf RPC guichet + verify ticket",
      ],
      phase1: [
        "Staging Hetzner + Docker Supabase",
        "pg_dump prod → restore staging",
        "Redéployer 7 Edge Functions",
      ],
      phase2: [
        "Login, FedaPay, guichet, QR, caisse, RLS, TPE",
      ],
      phase3: [
        "Cutover + webhook FedaPay + rollback Cloud 7–14 j",
      ],
    },
  };
}
