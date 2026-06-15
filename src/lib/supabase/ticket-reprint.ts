import { supabase } from "@/lib/supabase";
import { getTripDetailSupabase } from "@/lib/supabase/trip-detail";
import type { CompanyTicketSaleRow } from "@/lib/supabase/cancellation";
import type { TicketReceiptInput } from "@/lib/ticket-receipt-print";
import { counterTicketToReceiptInput } from "@/components/seller/SellerTicketReceiptPanel.tsx";

function num(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function routeParts(routeLabel: string): { originCity: string; destCity: string } {
  const parts = routeLabel.split(/\s*(?:→|->|—|-)\s*/);
  return {
    originCity: parts[0]?.trim() || routeLabel,
    destCity: parts[1]?.trim() || "?",
  };
}

export async function buildCounterTicketReprintInput(
  row: CompanyTicketSaleRow,
  companyName: string,
): Promise<TicketReceiptInput> {
  const { data: booking, error } = await supabase
    .from("ReservationBus")
    .select(
      "id, reservationId, price, passengerName, seatNumber, verifyToken, parcelCount, parcelWeight, parcelAmount, paymentId",
    )
    .eq("id", row.bookingId)
    .maybeSingle();

  if (error) throw error;

  let passengerPhone: string | undefined;
  if (booking?.paymentId) {
    const { data: payment, error: paymentError } = await supabase
      .from("Payment")
      .select("phone")
      .eq("id", booking.paymentId as string)
      .maybeSingle();
    if (paymentError) throw paymentError;
    const phone = payment?.phone ? String(payment.phone).trim() : "";
    if (phone && phone !== "0000000000") passengerPhone = phone;
  }

  const parcelCount = num(booking?.parcelCount);
  const parcelWeight = num(booking?.parcelWeight);
  const parcelAmount = num(booking?.parcelAmount);
  const totalPrice = num(booking?.price) || row.ticketAmount;
  const passengerName = String(booking?.passengerName ?? row.passengerName);
  const seatNumber = (booking?.seatNumber as string | null) ?? row.seatNumber;
  const verifyToken = (booking?.verifyToken as string | null) ?? null;

  const trip = booking?.reservationId
    ? await getTripDetailSupabase(booking.reservationId as string)
    : null;

  if (trip) {
    return counterTicketToReceiptInput(
      {
        reference: row.reference,
        verifyToken,
        totalPrice,
        currency: row.currency,
        passengerName,
        passengerPhone,
        seatNumber: seatNumber ?? undefined,
        parcelCount,
        parcelWeight,
        parcelAmount,
      },
      trip,
      companyName,
    );
  }

  const { originCity, destCity } = routeParts(row.routeLabel);
  const parcel =
    parcelCount > 0 || parcelWeight > 0 || parcelAmount > 0
      ? { count: parcelCount, weight: parcelWeight, amount: parcelAmount }
      : null;

  return {
    reference: row.reference,
    verifyToken,
    passengerName,
    passengerPhone,
    seatNumber,
    totalPrice,
    companyName,
    parcel,
    trip: {
      originCity,
      destCity,
      departureTime: row.departureTime,
      priceAmount: Math.max(0, totalPrice - parcelAmount),
      currency: row.currency,
    },
  };
}
