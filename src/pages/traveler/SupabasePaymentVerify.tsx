import { useEffect, useState } from "react";
import { useSearchParams, Link, useParams } from "react-router-dom";
import {
  CheckCircleIcon,
  XCircleIcon,
  Loader2Icon,
  TicketIcon,
  HomeIcon,
  AlertCircleIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import {
  Authenticated,
  AuthLoading,
} from "@/components/auth/AuthBoundary.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { useTranslation } from "react-i18next";
import { verifyPaymentSupabase } from "@/lib/supabase/payments.ts";
import { clearBookingDraft } from "@/lib/supabase/booking-draft";

type VerifyStatus = "verifying" | "success" | "failed" | "sold_out";

function SupabaseVerifyInner() {
  const { t } = useTranslation("traveler");
  const { lng } = useParams<{ lng: string }>();
  const [searchParams] = useSearchParams();

  const reservationId = searchParams.get("reservationId");
  const failedStatus = searchParams.get("status");
  const fedaPayTxnId = searchParams.get("id");
  const fedaReference = searchParams.get("reference");
  const paymentGateway = searchParams.get("gateway") ?? undefined;

  const [status, setStatus] = useState<VerifyStatus>(
    failedStatus === "failed" ||
      failedStatus === "declined" ||
      failedStatus === "canceled"
      ? "failed"
      : "verifying",
  );
  const [resolvedBookingId, setResolvedBookingId] = useState<string | null>(null);
  const [ticketReference, setTicketReference] = useState<string | null>(null);

  useEffect(() => {
    if (
      failedStatus === "failed" ||
      failedStatus === "declined" ||
      failedStatus === "canceled"
    ) {
      return;
    }

    let cancelled = false;

    const verify = async () => {
      const isApproved =
        failedStatus === "approved" ||
        failedStatus === "transferred" ||
        failedStatus === "success" ||
        failedStatus === "completed";

      if (!fedaPayTxnId && !fedaReference && !isApproved) {
        if (!cancelled) setStatus("failed");
        return;
      }

      try {
        const result = await verifyPaymentSupabase({
          transactionId: fedaPayTxnId ?? undefined,
          reference: fedaReference ?? undefined,
          reservationId: reservationId ?? undefined,
          gateway: paymentGateway,
        });

        if (cancelled) return;

        if (result.success && result.bookingId) {
          if (reservationId) clearBookingDraft(reservationId);
          setResolvedBookingId(result.bookingId);
          setTicketReference(result.reference ?? result.references?.join(", ") ?? null);
          setStatus("success");
          return;
        }

        if (result.code === "SOLD_OUT") {
          setStatus("sold_out");
          return;
        }

        if (isApproved && (fedaPayTxnId || fedaReference)) {
          await new Promise((r) => setTimeout(r, 2000));
          if (cancelled) return;
          const retry = await verifyPaymentSupabase({
            transactionId: fedaPayTxnId ?? undefined,
            reference: fedaReference ?? undefined,
            reservationId: reservationId ?? undefined,
            gateway: paymentGateway,
          });
          if (retry.success && retry.bookingId) {
            if (reservationId) clearBookingDraft(reservationId);
            setResolvedBookingId(retry.bookingId);
            setTicketReference(retry.reference ?? retry.references?.join(", ") ?? null);
            setStatus("success");
            return;
          }
        }

        setStatus("failed");
      } catch (err) {
        const error = err as Error & { code?: string };
        if (!cancelled) {
          if (error.code === "SOLD_OUT") {
            setStatus("sold_out");
          } else {
            setStatus("failed");
          }
        }
      }
    };

    void verify();
    return () => {
      cancelled = true;
    };
  }, [failedStatus, fedaPayTxnId, fedaReference, reservationId, paymentGateway]);

  if (status === "verifying") {
    return (
      <div className="max-w-md mx-auto px-4 py-16 text-center space-y-4">
        <div className="w-16 h-16 rounded-full bg-primary/10 flex items-center justify-center mx-auto">
          <Loader2Icon className="w-8 h-8 text-primary animate-spin" />
        </div>
        <h1 className="text-xl font-extrabold">{t("payment.verifying")}</h1>
        <p className="text-sm text-muted-foreground">
          {t("payment.verifying_desc")}
        </p>
      </div>
    );
  }

  if (status === "sold_out") {
    return (
      <div className="max-w-md mx-auto px-4 py-16 text-center space-y-4">
        <div className="w-16 h-16 rounded-full bg-amber-500/10 flex items-center justify-center mx-auto">
          <AlertCircleIcon className="w-8 h-8 text-amber-500" />
        </div>
        <h1 className="text-xl font-extrabold">Siège plus disponible</h1>
        <p className="text-sm text-muted-foreground">
          Votre paiement a été reçu mais le départ est complet. Contactez le
          support Tibus avec votre référence de transaction gateway.
        </p>
        <div className="flex gap-3 justify-center pt-4">
          <Link to={`/${lng}/traveler/search`}>
            <Button className="cursor-pointer">Rechercher un autre trajet</Button>
          </Link>
        </div>
      </div>
    );
  }

  if (status === "failed") {
    return (
      <div className="max-w-md mx-auto px-4 py-16 text-center space-y-4">
        <div className="w-16 h-16 rounded-full bg-red-500/10 flex items-center justify-center mx-auto">
          <XCircleIcon className="w-8 h-8 text-red-500" />
        </div>
        <h1 className="text-xl font-extrabold">{t("payment.failed")}</h1>
        <p className="text-sm text-muted-foreground">
          {t("payment.failed_desc")}
        </p>
        <div className="flex gap-3 justify-center pt-4">
          {reservationId && (
            <Link to={`/${lng}/trip/${reservationId}`}>
              <Button variant="secondary" className="cursor-pointer">
                Réessayer
              </Button>
            </Link>
          )}
          <Link to={`/${lng}/traveler`}>
            <Button className="cursor-pointer">
              <HomeIcon className="w-4 h-4 mr-2" /> {t("nav.home", { ns: "common" })}
            </Button>
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-md mx-auto px-4 py-16 text-center space-y-4">
      <div className="w-16 h-16 rounded-full bg-green-500/10 flex items-center justify-center mx-auto">
        <CheckCircleIcon className="w-8 h-8 text-green-500" />
      </div>
      <h1 className="text-xl font-extrabold">{t("payment.success")}</h1>
      <p className="text-sm text-muted-foreground">
        {t("payment.success_desc")}
      </p>
      {ticketReference && (
        <p className="text-xs font-mono text-muted-foreground">
          Ticket {ticketReference}
        </p>
      )}
      <div className="flex gap-3 justify-center pt-4">
        {resolvedBookingId && (
          <Link to={`/${lng}/booking/${resolvedBookingId}`}>
            <Button className="cursor-pointer">
              <TicketIcon className="w-4 h-4 mr-2" /> {t("payment.view_ticket")}
            </Button>
          </Link>
        )}
        <Link to={`/${lng}/traveler/bookings`}>
          <Button variant="secondary" className="cursor-pointer">
            {t("my_bookings")}
          </Button>
        </Link>
      </div>
    </div>
  );
}

export default function SupabasePaymentVerify() {
  return (
    <>
      <AuthLoading>
        <div className="max-w-md mx-auto px-4 py-16">
          <Skeleton className="h-40 w-full rounded-xl" />
        </div>
      </AuthLoading>
      <Authenticated>
        <SupabaseVerifyInner />
      </Authenticated>
    </>
  );
}
