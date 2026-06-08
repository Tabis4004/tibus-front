import { useEffect, useState } from "react";
import { useSearchParams, Link, useParams } from "react-router-dom";
import { useAction, useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import type { Id } from "@/convex/_generated/dataModel.d.ts";
import { CheckCircleIcon, XCircleIcon, Loader2Icon, TicketIcon, HomeIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Authenticated, AuthLoading } from "@/components/auth/AuthBoundary.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { useTranslation } from "react-i18next";

function VerifyInner() {
  const { t } = useTranslation("traveler");
  const { lng } = useParams<{ lng: string }>();
  const [searchParams] = useSearchParams();

  // FedaPay redirects back with the bookingId we passed in callback_url
  const bookingIdParam = searchParams.get("bookingId");
  const failedStatus = searchParams.get("status");

  // FedaPay also passes the transaction id in the redirect URL (?id=...)
  const fedaPayTxnId = searchParams.get("id");

  // Also support legacy Paystack params
  const paystackRef = searchParams.get("reference") ?? searchParams.get("trxref");

  const verifyFedaPay = useAction(api.fedaPayment.verifyPayment);

  // Try to get booking to find the payment reference
  const booking = useQuery(
    api.bookings.getBooking,
    bookingIdParam ? { bookingId: bookingIdParam as Id<"bookings"> } : "skip",
  );

  const [status, setStatus] = useState<"verifying" | "success" | "failed">(
    failedStatus === "failed" || failedStatus === "declined" || failedStatus === "canceled"
      ? "failed"
      : "verifying"
  );
  const [resolvedBookingId, setResolvedBookingId] = useState<string | null>(bookingIdParam);

  useEffect(() => {
    if (failedStatus === "failed" || failedStatus === "declined" || failedStatus === "canceled") return;

    let cancelled = false;

    const verify = async () => {
      // If FedaPay status says approved/transferred, or if we have an id or reference, verify
      const isFedaPayApproved = failedStatus === "approved" || failedStatus === "transferred";

      // Check if booking is already confirmed (e.g. webhook already fired)
      if (booking && (booking.paymentStatus === "paid" || booking.status === "confirmed")) {
        if (!cancelled) {
          setStatus("success");
          setResolvedBookingId(booking._id);
        }
        return;
      }

      // If we have a bookingId but no booking yet, the query may still be loading
      if (bookingIdParam && booking === undefined) return;

      // Build verification params
      const reference = paystackRef ?? booking?.paystackReference;
      const transactionId = fedaPayTxnId ?? undefined;

      // We need at least a transactionId or reference to verify
      if (!transactionId && !reference) {
        if (!cancelled) setStatus("failed");
        return;
      }

      try {
        const result = await verifyFedaPay({
          transactionId: transactionId ?? undefined,
          reference: reference ?? undefined,
        });
        if (cancelled) return;
        if (result.success && result.bookingId) {
          setStatus("success");
          setResolvedBookingId(result.bookingId);
        } else {
          // If FedaPay says approved but verify didn't confirm, retry once with small delay
          if (isFedaPayApproved && transactionId) {
            await new Promise((r) => setTimeout(r, 2000));
            if (cancelled) return;
            const retry = await verifyFedaPay({
              transactionId,
              reference: reference ?? undefined,
            });
            if (cancelled) return;
            if (retry.success && retry.bookingId) {
              setStatus("success");
              setResolvedBookingId(retry.bookingId);
              return;
            }
          }
          setStatus("failed");
        }
      } catch {
        if (!cancelled) {
          setStatus("failed");
        }
      }
    };

    verify();
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [booking, failedStatus, paystackRef, bookingIdParam, fedaPayTxnId]);

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
          <Link to={`/${lng}/traveler/bookings`}>
            <Button variant="secondary" className="cursor-pointer">
              <TicketIcon className="w-4 h-4 mr-2" /> {t("my_bookings")}
            </Button>
          </Link>
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

export default function PaymentVerify() {
  return (
    <>
      <AuthLoading>
        <div className="max-w-md mx-auto px-4 py-16">
          <Skeleton className="h-40 w-full rounded-xl" />
        </div>
      </AuthLoading>
      <Authenticated>
        <VerifyInner />
      </Authenticated>
    </>
  );
}
