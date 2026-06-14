import { useCallback, useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { ScanLineIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { isSupabaseAuth } from "@/lib/auth/config";
import { parseTicketQrPayload } from "@/lib/ticket-verify-url.ts";
import {
  confirmPassengerOnBoardSupabase,
  verifyTicketQrSupabase,
  type VerifiedTicket,
} from "@/lib/supabase/ticket-verify.ts";
import QrScanner from "@/pages/verify/_components/QrScanner.tsx";
import ManualTicketVerifyForm from "@/pages/verify/_components/ManualTicketVerifyForm.tsx";
import TicketScanResult from "@/pages/verify/_components/TicketScanResult.tsx";

const SCANNER_ROLES = ["owner", "controleur", "vendeur", "chauffeur", "super_admin"] as const;

function vibrateForResult(ticket: VerifiedTicket) {
  if (!navigator.vibrate) return;
  if (ticket.valid) navigator.vibrate(120);
  else if (ticket.result === "duplicate") navigator.vibrate([60, 40, 60]);
  else navigator.vibrate([80, 60, 80]);
}

function resolveToastMessage(ticket: VerifiedTicket, t: (key: string) => string): string {
  if (ticket.result === "wrong_company") return t("scanner.wrong_company_message");
  if (ticket.message === "already_on_board") return t("scanner.already_on_board_message");
  if (ticket.message === "passenger_boarded") return t("scanner.passenger_boarded_message");
  return ticket.message;
}

export default function TicketScannerPage() {
  const { lng } = useParams<{ lng: string }>();
  const { t } = useTranslation("common");
  const navigate = useNavigate();
  const appUser = useAppUser();
  const [result, setResult] = useState<VerifiedTicket | null>(null);
  const [checking, setChecking] = useState(false);
  const [markingOnBoard, setMarkingOnBoard] = useState(false);

  const hasAccess = SCANNER_ROLES.some((role) => appUser.roles.includes(role));

  useEffect(() => {
    if (!appUser.isReady || appUser.isLoading) return;
    if (!isSupabaseAuth()) {
      navigate(`/${lng ?? "fr"}`, { replace: true });
      return;
    }
    if (!hasAccess) {
      navigate(`/${lng ?? "fr"}`, { replace: true });
    }
  }, [appUser.isReady, appUser.isLoading, hasAccess, navigate, lng]);

  const runVerify = useCallback(
    async (input: { reference: string; token?: string | null; manualReference?: boolean }) => {
      setChecking(true);
      try {
        const verified = await verifyTicketQrSupabase({
          reference: input.reference,
          token: input.token ?? null,
          recordBoarding: true,
          manualReference: input.manualReference,
        });
        setResult(verified);
        vibrateForResult(verified);
        if (verified.result === "on_board") {
          toast.error(resolveToastMessage(verified, t));
        } else if (verified.result === "duplicate") {
          toast.warning(resolveToastMessage(verified, t));
        } else if (!verified.valid && verified.message) {
          toast.error(resolveToastMessage(verified, t));
        } else if (verified.result === "wrong_company") {
          toast.error(resolveToastMessage(verified, t));
        }
      } catch (err) {
        const message =
          err instanceof Error
            ? err.message
            : typeof err === "object" &&
                err &&
                "message" in err &&
                typeof err.message === "string"
              ? err.message
              : "Vérification impossible";
        toast.error(message);
        setResult({
          valid: false,
          result: "not_found",
          message,
          bookingReference: input.reference,
          passengerName: "",
          status: "cancelled",
          paymentStatus: "pending",
          totalPrice: 0,
          currency: "XOF",
          trip: null,
          origin: null,
          destination: null,
          originLoc: null,
          destLoc: null,
          bus: null,
        });
      } finally {
        setChecking(false);
      }
    },
    [],
  );

  const handleScan = useCallback(
    async (payload: string) => {
      const parsed = parseTicketQrPayload(payload);
      if (!parsed.reference) {
        toast.error("QR code non reconnu");
        return;
      }
      await runVerify({
        reference: parsed.reference,
        token: parsed.token,
        manualReference: false,
      });
    },
    [runVerify],
  );

  const handleManualVerify = useCallback(
    async (reference: string) => {
      await runVerify({
        reference,
        manualReference: true,
      });
    },
    [runVerify],
  );

  const handleMarkOnBoard = useCallback(async () => {
    if (!result?.bookingReference) return;
    setMarkingOnBoard(true);
    try {
      const updated = await confirmPassengerOnBoardSupabase(result.bookingReference);
      setResult(updated);
      vibrateForResult(updated);
      toast.success(resolveToastMessage(updated, t));
    } catch (err) {
      const message =
        err instanceof Error
          ? err.message
          : typeof err === "object" &&
              err &&
              "message" in err &&
              typeof err.message === "string"
            ? err.message
            : t("scanner.verify_failed");
      toast.error(message);
    } finally {
      setMarkingOnBoard(false);
    }
  }, [result?.bookingReference, t]);

  if (appUser.isLoading) {
    return (
      <div className="max-w-lg mx-auto px-4 py-6 space-y-4">
        <Skeleton className="h-10 w-56" />
        <Skeleton className="h-[360px] w-full rounded-2xl" />
      </div>
    );
  }

  if (!hasAccess) return null;

  return (
    <div className="max-w-lg mx-auto px-4 py-4 pb-28 space-y-5">
      <div className="text-center space-y-1">
        <div className="inline-flex items-center justify-center w-12 h-12 rounded-2xl bg-primary/10 text-primary mb-1">
          <ScanLineIcon className="w-6 h-6" />
        </div>
        <h1 className="text-xl font-extrabold">{t("scanner.title")}</h1>
        <p className="text-sm text-muted-foreground">{t("scanner.subtitle")}</p>
      </div>

      {result ? (
        <div className="space-y-4">
          <TicketScanResult
            ticket={result}
            onMarkOnBoard={() => void handleMarkOnBoard()}
            markingOnBoard={markingOnBoard}
          />
          <Button
            className="w-full cursor-pointer"
            size="lg"
            onClick={() => setResult(null)}
          >
            {t("scanner.scan_another")}
          </Button>
        </div>
      ) : (
        <>
          <QrScanner onScan={(payload) => void handleScan(payload)} paused={checking} />
          {checking ? (
            <p className="text-center text-sm text-muted-foreground animate-pulse">
              Vérification en cours…
            </p>
          ) : null}
        </>
      )}

      <ManualTicketVerifyForm
        onSubmit={(reference) => void handleManualVerify(reference)}
        disabled={checking}
      />
    </div>
  );
}
