export type BookingDraft = {
  reservationId: string;
  passengerName: string;
  passengerPhone: string;
  selectedSeat: string | null;
  promoCode: string;
  promoId?: string;
  discountAmount?: number;
  loyaltyPointsRedeemed?: number;
  loyaltyDiscountAmount?: number;
  platformLoyaltyPointsRedeemed?: number;
  platformLoyaltyDiscountAmount?: number;
  savedAt: string;
};

const DRAFT_PREFIX = "tibus:booking-draft:";

function draftKey(reservationId: string) {
  return `${DRAFT_PREFIX}${reservationId}`;
}

export function saveBookingDraft(draft: BookingDraft) {
  sessionStorage.setItem(draftKey(draft.reservationId), JSON.stringify(draft));
}

export function loadBookingDraft(
  reservationId: string,
): BookingDraft | null {
  const raw = sessionStorage.getItem(draftKey(reservationId));
  if (!raw) return null;
  try {
    return JSON.parse(raw) as BookingDraft;
  } catch {
    return null;
  }
}

export function clearBookingDraft(reservationId: string) {
  sessionStorage.removeItem(draftKey(reservationId));
}
