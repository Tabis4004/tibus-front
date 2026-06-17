import { format, parseISO } from "date-fns";
import {
  CheckCircleIcon,
  PackageIcon,
  TruckIcon,
  XCircleIcon,
} from "lucide-react";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { colisPublicReference } from "@/lib/colis-receipt.ts";
import {
  COLIS_SCAN_STEPS,
  colisScanAction,
  colisStatutLabel,
  colisStepIndex,
} from "@/lib/colis-scan.ts";
import type { ColisAutonomeDetail } from "@/lib/supabase/colis-autonomes.ts";

function fmt(iso: string, pattern: string) {
  try {
    return format(parseISO(iso), pattern);
  } catch {
    return iso;
  }
}

export default function ColisScanResult({
  detail,
  onAdvance,
  advancing = false,
}: {
  detail: ColisAutonomeDetail;
  onAdvance?: () => void;
  advancing?: boolean;
}) {
  const action = colisScanAction(detail);
  const currentStep = colisStepIndex(detail.statutColis);
  const isDone = detail.statutColis === "livre";
  const ref = colisPublicReference(detail.id);

  return (
    <div className="space-y-4">
      <div
        className={`rounded-2xl border overflow-hidden ${
          isDone ? "border-green-500/30" : "border-primary/30"
        }`}
      >
        <div
          className={`px-4 py-3 text-white ${
            isDone ? "bg-green-600" : "bg-primary"
          }`}
        >
          <div className="flex items-center gap-2">
            {isDone ? (
              <CheckCircleIcon className="w-5 h-5 shrink-0" />
            ) : (
              <PackageIcon className="w-5 h-5 shrink-0" />
            )}
            <div>
              <p className="font-bold text-sm">
                {isDone ? "Colis livré" : action?.label ?? "Colis identifié"}
              </p>
              <p className="text-xs text-white/85 font-mono">{ref}</p>
            </div>
          </div>
        </div>

        <div className="p-4 space-y-3 bg-card">
          <div className="flex flex-wrap gap-1.5">
            {COLIS_SCAN_STEPS.map((step, index) => {
              const done = index < currentStep;
              const active = index === currentStep;
              return (
                <Badge
                  key={step.statut}
                  variant={active ? "default" : done ? "secondary" : "outline"}
                  className="text-[10px]"
                >
                  {step.label}
                </Badge>
              );
            })}
          </div>

          <div className="space-y-1 text-sm">
            <p>
              <span className="text-muted-foreground">Trajet :</span>{" "}
              <span className="font-semibold">
                {detail.gareDepart} → {detail.gareDestination}
              </span>
            </p>
            <p>
              <span className="text-muted-foreground">Expéditeur :</span> {detail.nomExpediteur}
            </p>
            <p>
              <span className="text-muted-foreground">Destinataire :</span>{" "}
              <span className="font-semibold">{detail.nomDestinataire}</span>
            </p>
            <p>
              <span className="text-muted-foreground">Nature :</span>{" "}
              {detail.natures.join(", ") || "—"}
            </p>
            {detail.descriptionContenu ? (
              <p className="text-xs text-muted-foreground break-words">
                Description : {detail.descriptionContenu}
              </p>
            ) : null}
            <p>
              <span className="text-muted-foreground">Statut :</span>{" "}
              {colisStatutLabel(detail.statutColis)}
            </p>
            <p className="text-xs text-muted-foreground">
              Enregistré le {fmt(detail.createdAt, "dd/MM/yyyy HH:mm")}
            </p>
          </div>

          {action && onAdvance ? (
            <div className="space-y-2 pt-1">
              <p className="text-xs text-muted-foreground">{action.description}</p>
              <Button
                className="w-full cursor-pointer gap-2"
                size="lg"
                disabled={advancing}
                onClick={onAdvance}
              >
                <TruckIcon className="w-4 h-4" />
                {advancing ? "…" : action.label}
              </Button>
            </div>
          ) : null}

          {isDone ? (
            <p className="text-sm text-green-700 dark:text-green-400 flex items-center gap-2">
              <CheckCircleIcon className="w-4 h-4" />
              Ce colis a déjà été remis au destinataire.
            </p>
          ) : null}
        </div>
      </div>
    </div>
  );
}

export function ColisScanError({ message }: { message: string }) {
  return (
    <div className="rounded-2xl border border-red-500/30 bg-red-500/5 p-4 flex items-start gap-3">
      <XCircleIcon className="w-5 h-5 text-red-600 shrink-0 mt-0.5" />
      <div>
        <p className="font-semibold text-sm">Scan refusé</p>
        <p className="text-sm text-muted-foreground mt-1">{message}</p>
      </div>
    </div>
  );
}
