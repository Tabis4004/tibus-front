import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { format } from "date-fns";
import { CheckIcon, MegaphoneIcon, UndoIcon } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog.tsx";
import { errorMessage } from "@/lib/utils";
import {
  listTripIncidentsSupabase,
  setTripIncidentStatusSupabase,
  TRIP_INCIDENT_CATEGORY_LABELS,
  type TripIncident,
  type TripIncidentCategory,
} from "@/lib/supabase/trip-incidents.ts";

function categoryLabel(category: string): string {
  return (
    TRIP_INCIDENT_CATEGORY_LABELS[category as TripIncidentCategory] ?? category
  );
}

// Reporting des incidents signalés par les voyageurs sur un voyage donné.
export default function TripIncidentsDialog({
  reservationId,
  tripLabel,
  onClose,
}: {
  reservationId: string;
  tripLabel: string;
  onClose: () => void;
}) {
  const { t } = useTranslation("owner");
  const [incidents, setIncidents] = useState<TripIncident[] | undefined>(undefined);
  const [busyId, setBusyId] = useState<string | null>(null);

  const load = () => {
    setIncidents(undefined);
    void listTripIncidentsSupabase(reservationId)
      .then(setIncidents)
      .catch((err) => {
        toast.error(errorMessage(err, t("trips.incidents_load_error", { defaultValue: "Chargement des incidents impossible." })));
        setIncidents([]);
      });
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [reservationId]);

  const toggleStatus = async (incident: TripIncident) => {
    const next = incident.status === "nouveau" ? "traite" : "nouveau";
    setBusyId(incident.id);
    try {
      await setTripIncidentStatusSupabase(incident.id, next);
      setIncidents((current) =>
        (current ?? []).map((row) =>
          row.id === incident.id ? { ...row, status: next } : row,
        ),
      );
    } catch (err) {
      toast.error(errorMessage(err, t("trips.incident_status_error", { defaultValue: "Mise à jour impossible." })));
    } finally {
      setBusyId(null);
    }
  };

  return (
    <Dialog open onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <MegaphoneIcon className="w-4 h-4" />
            {t("trips.incidents_title", { defaultValue: "Incidents signalés" })}
          </DialogTitle>
          <p className="text-xs text-muted-foreground">{tripLabel}</p>
        </DialogHeader>

        {incidents === undefined ? (
          <Skeleton className="h-32 w-full" />
        ) : incidents.length === 0 ? (
          <p className="text-sm text-muted-foreground py-6 text-center">
            {t("trips.incidents_none", {
              defaultValue: "Aucun incident signalé sur ce voyage.",
            })}
          </p>
        ) : (
          <div className="space-y-3">
            {incidents.map((incident) => (
              <div key={incident.id} className="rounded-lg border p-3 space-y-1.5">
                <div className="flex items-center gap-2 flex-wrap">
                  <Badge
                    variant={incident.status === "nouveau" ? "destructive" : "secondary"}
                    className="text-[10px]"
                  >
                    {incident.status === "nouveau"
                      ? t("trips.incident_new", { defaultValue: "Nouveau" })
                      : t("trips.incident_handled", { defaultValue: "Traité" })}
                  </Badge>
                  <Badge variant="outline" className="text-[10px]">
                    {categoryLabel(incident.category)}
                  </Badge>
                  <span className="text-[11px] text-muted-foreground ml-auto">
                    {incident.createdAt
                      ? format(new Date(incident.createdAt), "dd/MM/yyyy HH:mm")
                      : ""}
                  </span>
                </div>
                <p className="text-sm whitespace-pre-wrap">{incident.message}</p>
                <div className="flex items-center justify-between gap-2 text-xs text-muted-foreground">
                  <span className="truncate">
                    {incident.reporterName}
                    {incident.reporterPhone ? ` · ${incident.reporterPhone}` : ""}
                    {incident.ticketReference ? ` · ${incident.ticketReference}` : ""}
                  </span>
                  <Button
                    size="sm"
                    variant="outline"
                    className="h-7 text-xs shrink-0"
                    disabled={busyId === incident.id}
                    onClick={() => void toggleStatus(incident)}
                  >
                    {incident.status === "nouveau" ? (
                      <>
                        <CheckIcon className="w-3 h-3 mr-1" />
                        {t("trips.incident_mark_handled", { defaultValue: "Marquer traité" })}
                      </>
                    ) : (
                      <>
                        <UndoIcon className="w-3 h-3 mr-1" />
                        {t("trips.incident_reopen", { defaultValue: "Rouvrir" })}
                      </>
                    )}
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
