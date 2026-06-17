import { useCallback, useState } from "react";
import { KeyboardIcon, PackageIcon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { parseColisQrPayload } from "@/lib/colis-verify.ts";
import { colisPublicReference } from "@/lib/colis-receipt.ts";
import { colisScanAction } from "@/lib/colis-scan.ts";
import {
  deliverColisAutonomeSupabase,
  getColisAutonomeDetailSupabase,
  resolveColisRetraitCodeSupabase,
  updateColisStatutSupabase,
  type ColisAutonomeDetail,
  type ColisSmsPayload,
} from "@/lib/supabase/colis-autonomes.ts";
import { supabaseErrorMessage } from "@/lib/supabase/errors";
import QrScanner from "@/pages/verify/_components/QrScanner.tsx";
import ColisScanResult, { ColisScanError } from "@/pages/verify/_components/ColisScanResult.tsx";

async function maybeSendColisSms(colisId: string, sms: ColisSmsPayload) {
  if (!sms.send || !sms.message) return;
  const phones = [sms.expediteurPhone, sms.destinatairePhone].filter(Boolean) as string[];
  if (!phones.length) return;
  const { sendColisSmsSupabase } = await import("@/lib/supabase/colis-autonomes.ts");
  try {
    await sendColisSmsSupabase({
      colisId,
      statut: "livre",
      message: sms.message,
      phones,
    });
  } catch {
    // SMS optionnel après scan
  }
}

export default function ColisScanWorkflow({
  onAdvanced,
}: {
  onAdvanced?: () => void;
}) {
  const [manualRef, setManualRef] = useState("");
  const [detail, setDetail] = useState<ColisAutonomeDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [advancing, setAdvancing] = useState(false);

  const lookupColis = useCallback(async (raw: string) => {
    const parsed = parseColisQrPayload(raw);
    if (!parsed) {
      setDetail(null);
      setError("QR ou référence non reconnue — utilisez CL-XXXXXXXX");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const colisId = await resolveColisRetraitCodeSupabase(parsed);
      if (!colisId) throw new Error("Colis introuvable");
      const nextDetail = await getColisAutonomeDetailSupabase(colisId);
      if (!nextDetail) throw new Error("Colis introuvable");
      setDetail(nextDetail);
      setManualRef(colisPublicReference(nextDetail.id));
    } catch (err) {
      setDetail(null);
      setError(supabaseErrorMessage(err, "Colis introuvable"));
    } finally {
      setLoading(false);
    }
  }, []);

  const handleAdvance = async () => {
    if (!detail) return;
    const action = colisScanAction(detail);
    if (!action) return;

    setAdvancing(true);
    try {
      let nextDetail: ColisAutonomeDetail | null = detail;

      if (action.nextStatut === "livre") {
        const result = await deliverColisAutonomeSupabase(colisPublicReference(detail.id));
        await maybeSendColisSms(result.id, result.sms);
        toast.success(`Colis remis à ${result.nomDestinataire}`);
      } else {
        const result = await updateColisStatutSupabase(detail.id, action.nextStatut);
        if (result.sms.send && result.sms.message) {
          const phones = [result.sms.expediteurPhone, result.sms.destinatairePhone].filter(
            Boolean,
          ) as string[];
          if (phones.length) {
            const { sendColisSmsSupabase } = await import("@/lib/supabase/colis-autonomes.ts");
            await sendColisSmsSupabase({
              colisId: result.id,
              statut: result.statutColis,
              message: result.sms.message,
              phones,
            }).catch(() => undefined);
          }
        }
        toast.success(`Statut : ${action.label}`);
      }

      nextDetail = await getColisAutonomeDetailSupabase(detail.id);
      setDetail(nextDetail);
      onAdvanced?.();
    } catch (err) {
      toast.error(supabaseErrorMessage(err, "Action impossible"));
    } finally {
      setAdvancing(false);
    }
  };

  if (detail) {
    return (
      <div className="space-y-4">
        <ColisScanResult
          detail={detail}
          onAdvance={colisScanAction(detail) ? () => void handleAdvance() : undefined}
          advancing={advancing}
        />
        <Button
          variant="secondary"
          className="w-full cursor-pointer"
          onClick={() => {
            setDetail(null);
            setError(null);
            setManualRef("");
          }}
        >
          Scanner un autre colis
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <QrScanner
        onScan={(payload) => void lookupColis(payload)}
        paused={loading || advancing}
      />

      <div className="space-y-2">
        <Label htmlFor="colis-scan-ref" className="flex items-center gap-1.5 text-sm">
          <KeyboardIcon className="w-4 h-4" />
          Référence manuelle
        </Label>
        <div className="flex gap-2">
          <Input
            id="colis-scan-ref"
            className="font-mono text-xs uppercase"
            placeholder="CL-XXXXXXXX"
            value={manualRef}
            onChange={(e) => setManualRef(e.target.value.toUpperCase())}
            autoCapitalize="characters"
            autoComplete="off"
            spellCheck={false}
          />
          <Button
            variant="secondary"
            className="cursor-pointer shrink-0"
            disabled={loading || !manualRef.trim()}
            onClick={() => void lookupColis(manualRef.trim())}
          >
            {loading ? "…" : "Vérifier"}
          </Button>
        </div>
      </div>

      {error ? <ColisScanError message={error} /> : null}
    </div>
  );
}

export function ColisScanWorkflowHeader() {
  return (
    <div className="text-center space-y-1">
      <div className="inline-flex items-center justify-center w-12 h-12 rounded-2xl bg-primary/10 text-primary mb-1">
        <PackageIcon className="w-6 h-6" />
      </div>
      <h2 className="text-xl font-extrabold">Scanner colis</h2>
      <p className="text-sm text-muted-foreground">
        3 étapes : en soute → arrivé → remis au destinataire
      </p>
    </div>
  );
}
