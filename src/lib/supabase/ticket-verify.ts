import { supabase } from "@/lib/supabase";
import { normalizeTicketReference } from "@/lib/ticket-verify-url.ts";

export type TicketVerifyResultCode =
  | "valid"
  | "invalid"
  | "duplicate"
  | "cancelled"
  | "unpaid"
  | "not_found"
  | "wrong_company"
  | "forbidden"
  | "error"
  | "on_board";

function rpcErrorMessage(err: unknown): string {
  if (err && typeof err === "object") {
    const row = err as { message?: string; details?: string; hint?: string };
    if (row.message) return row.message;
    if (row.details) return row.details;
    if (row.hint) return row.hint;
  }
  if (err instanceof Error && err.message) return err.message;
  return "Vérification impossible";
}

export type VerifiedTicket = {
  valid: boolean;
  result: TicketVerifyResultCode;
  message: string;
  bookingId?: string;
  bookingReference: string;
  passengerName: string;
  passengerPhone?: string | null;
  seatNumber?: string | null;
  status: string;
  paymentStatus: "paid" | "pending";
  totalPrice: number;
  currency: string;
  createdAt?: string;
  companyId?: string;
  companyName?: string;
  boardedAt?: string | null;
  boardingScanCount?: number;
  onBoardAt?: string | null;
  onBoardScanCount?: number;
  trip: {
    departureTime: string;
    arrivalTime?: string | null;
  } | null;
  origin: { name: string } | null;
  destination: { name: string } | null;
  originLoc: { city: string } | null;
  destLoc: { city: string } | null;
  bus: { name: string; plateNumber?: string | null } | null;
};

function num(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function mapVerifiedTicket(row: Record<string, unknown>): VerifiedTicket {
  const tripRaw = row.trip as Record<string, unknown> | null | undefined;
  const busRaw = row.bus as Record<string, unknown> | null | undefined;
  const originRaw = row.origin as Record<string, unknown> | null | undefined;
  const destRaw = row.destination as Record<string, unknown> | null | undefined;
  const originLocRaw = row.originLoc as Record<string, unknown> | null | undefined;
  const destLocRaw = row.destLoc as Record<string, unknown> | null | undefined;

  return {
    valid: Boolean(row.valid),
    result: String(row.result ?? "not_found") as TicketVerifyResultCode,
    message: String(row.message ?? ""),
    bookingId: row.bookingId ? String(row.bookingId) : undefined,
    bookingReference: String(row.bookingReference ?? ""),
    passengerName: String(row.passengerName ?? ""),
    passengerPhone: row.passengerPhone ? String(row.passengerPhone) : null,
    seatNumber: row.seatNumber ? String(row.seatNumber) : null,
    status: String(row.status ?? "confirmed"),
    paymentStatus: row.paymentStatus === "pending" ? "pending" : "paid",
    totalPrice: num(row.totalPrice),
    currency: String(row.currency ?? "XOF"),
    createdAt: row.createdAt ? String(row.createdAt) : undefined,
    companyId: row.companyId ? String(row.companyId) : undefined,
    companyName: row.companyName ? String(row.companyName) : undefined,
    boardedAt: row.boardedAt ? String(row.boardedAt) : null,
    boardingScanCount: row.boardingScanCount == null ? undefined : num(row.boardingScanCount),
    onBoardAt: row.onBoardAt ? String(row.onBoardAt) : null,
    onBoardScanCount: row.onBoardScanCount == null ? undefined : num(row.onBoardScanCount),
    trip: tripRaw?.departureTime
      ? {
          departureTime: String(tripRaw.departureTime),
          arrivalTime: tripRaw.arrivalTime ? String(tripRaw.arrivalTime) : null,
        }
      : null,
    origin: originRaw?.name ? { name: String(originRaw.name) } : null,
    destination: destRaw?.name ? { name: String(destRaw.name) } : null,
    originLoc: originLocRaw?.city ? { city: String(originLocRaw.city) } : null,
    destLoc: destLocRaw?.city ? { city: String(destLocRaw.city) } : null,
    bus: busRaw?.name
      ? {
          name: String(busRaw.name),
          plateNumber: busRaw.plateNumber ? String(busRaw.plateNumber) : null,
        }
      : null,
  };
}

async function lookupTicketForVerify(reference: string): Promise<VerifiedTicket | null> {
  const { data, error } = await supabase.rpc("lookup_ticket_for_verify", {
    p_reference: reference,
  });
  if (error || !data || typeof data !== "object") return null;

  const row = data as Record<string, unknown>;
  if (!row.found) return null;

  const boardedAt = row.boardedAt ? String(row.boardedAt) : null;
  const onBoardAt = row.onBoardAt ? String(row.onBoardAt) : null;
  const tripRaw = row.trip as Record<string, unknown> | null | undefined;

  return {
    valid: false,
    result: onBoardAt ? "on_board" : boardedAt ? "duplicate" : "not_found",
    message: onBoardAt
      ? "already_on_board"
      : boardedAt
        ? "Billet déjà scanné à l'embarquement"
        : "Billet trouvé — exécutez le lot SQL 036 si l'embarquement échoue",
    bookingId: row.bookingId ? String(row.bookingId) : undefined,
    bookingReference: String(row.bookingReference ?? reference),
    passengerName: String(row.passengerName ?? ""),
    passengerPhone: row.passengerPhone ? String(row.passengerPhone) : null,
    seatNumber: row.seatNumber ? String(row.seatNumber) : null,
    status: "confirmed",
    paymentStatus: row.paymentStatus === "pending" ? "pending" : "paid",
    totalPrice: num(row.totalPrice),
    currency: String(row.currency ?? "XOF"),
    createdAt: row.createdAt ? String(row.createdAt) : undefined,
    companyId: row.companyId ? String(row.companyId) : undefined,
    companyName: row.companyName ? String(row.companyName) : undefined,
    boardedAt,
    boardingScanCount: row.boardingScanCount == null ? undefined : num(row.boardingScanCount),
    onBoardAt,
    onBoardScanCount: row.onBoardScanCount == null ? undefined : num(row.onBoardScanCount),
    trip: tripRaw?.departureTime
      ? {
          departureTime: String(tripRaw.departureTime),
          arrivalTime: tripRaw.arrivalTime ? String(tripRaw.arrivalTime) : null,
        }
      : null,
    origin: (row.origin as { name?: string } | null)?.name
      ? { name: String((row.origin as { name: string }).name) }
      : null,
    destination: (row.destination as { name?: string } | null)?.name
      ? { name: String((row.destination as { name: string }).name) }
      : null,
    originLoc: (row.originLoc as { city?: string } | null)?.city
      ? { city: String((row.originLoc as { city: string }).city) }
      : null,
    destLoc: (row.destLoc as { city?: string } | null)?.city
      ? { city: String((row.destLoc as { city: string }).city) }
      : null,
    bus: (row.bus as { name?: string; plateNumber?: string | null } | null)?.name
      ? {
          name: String((row.bus as { name: string }).name),
          plateNumber: (row.bus as { plateNumber?: string | null }).plateNumber
            ? String((row.bus as { plateNumber: string }).plateNumber)
            : null,
        }
      : null,
  };
}

export async function verifyTicketQrSupabase(input: {
  reference: string;
  token?: string | null;
  recordBoarding?: boolean;
  manualReference?: boolean;
}): Promise<VerifiedTicket> {
  let reference = normalizeTicketReference(input.reference);
  if (!reference) {
    return {
      valid: false,
      result: "not_found",
      message: "Numéro de billet vide",
      bookingReference: "",
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
    };
  }

  const manualReference =
    Boolean(input.manualReference) ||
    (Boolean(input.recordBoarding) && !input.token);

  const callVerify = async (ref: string) => {
    const { data, error } = await supabase.rpc("verify_ticket_qr", {
      p_reference: ref,
      p_token: input.token ?? null,
      p_record_boarding: Boolean(input.recordBoarding),
      p_manual_reference: manualReference,
    });
    if (error) throw error;
    return mapVerifiedTicket((data ?? {}) as Record<string, unknown>);
  };

  try {
    let result = await callVerify(reference);
    if (
      result.result === "not_found" ||
      result.result === "error" ||
      !result.passengerName
    ) {
      const lookup = await lookupTicketForVerify(reference);
      if (lookup) {
        if (result.result === "not_found" || result.result === "error") {
          result = await callVerify(lookup.bookingReference);
        }
        if (
          result.result === "not_found" ||
          result.result === "error" ||
          !result.passengerName
        ) {
          return lookup;
        }
      }
    }
    return result;
  } catch (err) {
    const lookup = await lookupTicketForVerify(reference);
    if (lookup) return lookup;
    throw new Error(rpcErrorMessage(err));
  }
}

export async function verifyTicketByReferenceSupabase(
  reference: string,
): Promise<VerifiedTicket | null> {
  try {
    const result = await verifyTicketQrSupabase({
      reference,
      manualReference: true,
      recordBoarding: false,
    });
    if (result.result === "not_found" && !result.bookingReference) return null;
    return result;
  } catch {
    return null;
  }
}

export async function confirmPassengerOnBoardSupabase(reference: string): Promise<VerifiedTicket> {
  const normalized = normalizeTicketReference(reference);
  const { data, error } = await supabase.rpc("confirm_passenger_on_board", {
    p_reference: normalized,
  });
  if (error) throw new Error(rpcErrorMessage(error));
  return mapVerifiedTicket((data ?? {}) as Record<string, unknown>);
}
