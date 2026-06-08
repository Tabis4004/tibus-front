import { printer } from "@/lib/printer.ts";
import type { ColisAutonomeDetail } from "@/lib/supabase/colis-autonomes.ts";
import { COLIS_STATUT_LABELS } from "@/lib/supabase/colis-autonomes.ts";

export async function printColisReceipt(detail: ColisAutonomeDetail, currency = "XOF") {
  const retraitCode = detail.id;
  const natures = detail.natures.length ? detail.natures.join(", ") : "—";

  await printer.printReceipt({
    header: detail.companyName || "TIBUS COLIS",
    lines: [
      { text: "RECU EXPEDITION COLIS", align: "center", bold: true },
      { text: "CONFIDENTIEL — CODE RETRAIT", align: "center", size: "small" },
      { text: "" },
      { text: `Code retrait:`, bold: true },
      { text: retraitCode, align: "center", size: "large", bold: true },
      { text: "" },
      { text: `Statut: ${COLIS_STATUT_LABELS[detail.statutColis]}` },
      { text: `Depart: ${detail.gareDepart}` },
      { text: `Destination: ${detail.gareDestination}` },
      { text: "" },
      { text: "EXPEDITEUR", bold: true },
      { text: detail.nomExpediteur },
      { text: detail.telephoneExpediteur, size: "small" },
      { text: "" },
      { text: "DESTINATAIRE", bold: true },
      { text: detail.nomDestinataire },
      { text: detail.telephoneDestinataire, size: "small" },
      { text: "" },
      { text: `Natures: ${natures}`, size: "small" },
      { text: `Pieces: ${detail.nombrePieces}` },
      { text: detail.poidsKg ? `Poids: ${detail.poidsKg} kg` : "Poids: —" },
      { text: detail.descriptionContenu ? `Contenu: ${detail.descriptionContenu}` : "" },
      { text: "" },
      { text: `Montant fret: ${detail.montantFret.toLocaleString()} ${currency}`, bold: true },
      { text: `Source: ${detail.sourceVente}`, size: "small" },
      { text: "" },
      { text: "Presentez ce code a la gare de destination.", align: "center", size: "small" },
    ],
    qr: retraitCode,
    qrSize: 220,
    feedLines: 4,
    cut: true,
  });
}
