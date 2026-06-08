/** Ticket émis uniquement après paiement confirmé — pas de blocage de siège avant. */
export function isIssuedTicket(
  isReservation: boolean,
  txID: string | null | undefined,
): boolean {
  return !isReservation || Boolean(txID);
}
