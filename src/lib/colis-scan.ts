import type { ColisAutonomeDetail, ColisStatut } from "@/lib/supabase/colis-autonomes.ts";
import { COLIS_STATUT_LABELS } from "@/lib/supabase/colis-autonomes.ts";

export type ColisScanAction = {
  nextStatut: ColisStatut;
  label: string;
  description: string;
};

const SCAN_ACTIONS: Partial<Record<ColisStatut, ColisScanAction>> = {
  enregistre: {
    nextStatut: "charge",
    label: "Charger en soute",
    description: "Confirmer que le colis est chargé dans le bus.",
  },
  charge: {
    nextStatut: "arrive",
    label: "Confirmer arrivée",
    description: "Le colis est arrivé à la gare de destination.",
  },
  arrive: {
    nextStatut: "livre",
    label: "Remettre au destinataire",
    description: "Remise du colis au destinataire sur présentation du reçu ou QR.",
  },
};

export function colisScanAction(detail: ColisAutonomeDetail): ColisScanAction | null {
  if (detail.statutColis === "livre") return null;
  return SCAN_ACTIONS[detail.statutColis] ?? null;
}

export const COLIS_SCAN_STEPS: Array<{ statut: ColisStatut; label: string }> = [
  { statut: "enregistre", label: "Enregistré" },
  { statut: "charge", label: "En soute" },
  { statut: "arrive", label: "Arrivé" },
  { statut: "livre", label: "Livré" },
];

export function colisStepIndex(statut: ColisStatut): number {
  return COLIS_SCAN_STEPS.findIndex((s) => s.statut === statut);
}

export function colisStatutLabel(statut: ColisStatut): string {
  return COLIS_STATUT_LABELS[statut];
}
