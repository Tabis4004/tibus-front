import { useCallback, useEffect, useRef, useState } from "react";
import { format, parseISO } from "date-fns";
import QRCode from "qrcode";
import {
  CheckCircleIcon,
  MessageCircleIcon,
  PlusIcon,
  PrinterIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import {
  buildColisTrackingWhatsAppMessage,
  colisPublicReference,
  colisQrPayload,
  isColisPosPrinterAvailable,
  openColisWhatsApp,
  printColisReceipt,
  printColisReceiptBrowser,
} from "@/lib/colis-receipt.ts";
import type { ColisAutonomeDetail } from "@/lib/supabase/colis-autonomes.ts";
import { COLIS_STATUT_LABELS } from "@/lib/supabase/colis-autonomes.ts";
import type { ThermalPaperWidth } from "@/lib/ticket-receipt-print.ts";
import type { SellerCompanyReceiptInfo } from "@/lib/supabase/seller-counter";
import ReceiptPoweredByFooter from "@/components/seller/ReceiptPoweredByFooter.tsx";

function fmt(iso: string, pattern: string) {
  try {
    return format(parseISO(iso), pattern);
  } catch {
    return iso;
  }
}

export default function ColisReceiptPanel({
  detail,
  currency = "XOF",
  companyInfo,
  autoPrint = false,
  showSuccessHeader = true,
  onBack,
  onNewShipment,
  onDone,
}: {
  detail: ColisAutonomeDetail;
  currency?: string;
  companyInfo?: SellerCompanyReceiptInfo;
  autoPrint?: boolean;
  showSuccessHeader?: boolean;
  onBack?: () => void;
  onNewShipment?: () => void;
  onDone?: () => void;
}) {
  const receiptRef = useRef<HTMLDivElement>(null);
  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);
  const autoPrintedRef = useRef(false);
  const reference = colisPublicReference(detail.id);
  const natureLabel = detail.natures.filter(Boolean).join(", ") || "—";
  const description = detail.descriptionContenu?.trim() || "—";
  const posNative = isColisPosPrinterAvailable();
  const companyName = companyInfo?.name || detail.companyName || "Tibus";

  useEffect(() => {
    void QRCode.toDataURL(colisQrPayload(detail), {
      width: 180,
      margin: 1,
      color: { dark: "#000000", light: "#ffffff" },
      errorCorrectionLevel: "M",
    })
      .then(setQrDataUrl)
      .catch(() => setQrDataUrl(null));
  }, [detail.id]);

  useEffect(() => {
    if (!autoPrint || autoPrintedRef.current || !qrDataUrl) return;
    if (!posNative) return;
    autoPrintedRef.current = true;
    printColisReceipt(detail, currency, "80mm");
  }, [autoPrint, currency, detail, posNative, qrDataUrl]);

  const handleThermalPrint = useCallback(
    (paperWidth: ThermalPaperWidth) => {
      if (isColisPosPrinterAvailable()) {
        printColisReceipt(detail, currency, paperWidth);
        return;
      }
      printColisReceiptBrowser(paperWidth);
    },
    [currency, detail],
  );

  const handleWhatsAppShare = useCallback(
    (recipient: "expediteur" | "destinataire") => {
      const phone = recipient === "expediteur" ? detail.telephoneExpediteur : detail.telephoneDestinataire;
      const message = buildColisTrackingWhatsAppMessage({
        colisId: detail.id,
        statut: detail.statutColis,
        companyName,
        gareDepart: detail.gareDepart,
        gareDestination: detail.gareDestination,
        recipientLabel: recipient === "expediteur" ? "Expéditeur" : "Destinataire",
      });
      openColisWhatsApp(phone, message);
    },
    [companyName, detail],
  );

  return (
    <div className="max-w-md mx-auto px-3 py-4 space-y-4">
      {showSuccessHeader && (
        <div className="text-center space-y-1 print-hide">
          <div className="w-12 h-12 rounded-full bg-green-500/10 flex items-center justify-center mx-auto">
            <CheckCircleIcon className="w-6 h-6 text-green-500" />
          </div>
          <h2 className="text-lg font-extrabold">Colis enregistré</h2>
          <p className="text-xs text-muted-foreground">
            Remettez le reçu à l&apos;expéditeur — retrait au scan QR ou référence {reference}
          </p>
        </div>
      )}

      <div
        id="printable-colis-receipt"
        ref={receiptRef}
        className="bg-white text-black py-3 rounded-lg border shadow-sm text-center space-y-2"
      >
        <div className="px-3 pb-2 border-b border-dashed border-black/30 space-y-1">
          {companyInfo?.logoUrl && (
            <img src={companyInfo.logoUrl} alt="Logo" className="h-10 mx-auto object-contain" />
          )}
          <div className="font-bold text-sm">{companyName}</div>
          {(companyInfo?.address || companyInfo?.phone || companyInfo?.email) && (
            <div className="text-[9px] text-gray-500 leading-tight">
              {companyInfo.address && <span>{companyInfo.address}</span>}
              {companyInfo.phone && <span> | {companyInfo.phone}</span>}
              {companyInfo.email && <span> | {companyInfo.email}</span>}
            </div>
          )}
        </div>

        <div className="text-[10px] uppercase tracking-widest text-gray-500">Référence colis</div>
        <p className="text-2xl font-extrabold tracking-widest" style={{ color: "#5b21b6" }}>
          {reference}
        </p>

        {qrDataUrl && (
          <div className="flex flex-col items-center gap-1 pt-1">
            <img src={qrDataUrl} alt="QR retrait" className="w-24 h-24 rounded" />
            <p className="text-[9px] text-gray-500">Scan pour retrait</p>
          </div>
        )}

        <div className="space-y-0.5 text-xs text-left px-3 pt-2">
          <div className="flex justify-between gap-1">
            <span className="text-gray-600">Expéditeur:</span>
            <span className="font-bold text-right">{detail.nomExpediteur}</span>
          </div>
          <div className="flex justify-between gap-1">
            <span className="text-gray-600">Tél. expéditeur:</span>
            <span className="text-right">{detail.telephoneExpediteur}</span>
          </div>
          <div className="flex justify-between gap-1">
            <span className="text-gray-600">Destinataire:</span>
            <span className="font-bold text-right">{detail.nomDestinataire}</span>
          </div>
          <div className="flex justify-between gap-1">
            <span className="text-gray-600">Tél. destinataire:</span>
            <span className="text-right">{detail.telephoneDestinataire}</span>
          </div>
          <div className="flex justify-between gap-1 border-t border-dashed border-black/20 pt-0.5 mt-0.5">
            <span className="text-gray-600">Trajet:</span>
            <span className="font-bold text-right">
              {detail.gareDepart} → {detail.gareDestination}
            </span>
          </div>
          <div className="flex justify-between gap-1">
            <span className="text-gray-600">Enregistré:</span>
            <span className="font-bold text-right">{fmt(detail.createdAt, "dd/MM/yyyy HH:mm")}</span>
          </div>
          <div className="flex justify-between gap-1">
            <span className="text-gray-600">Statut:</span>
            <span className="text-right">{COLIS_STATUT_LABELS[detail.statutColis]}</span>
          </div>
          <div className="flex justify-between gap-1 border-t border-dashed border-black/20 pt-0.5 mt-0.5">
            <span className="text-gray-600">Nature:</span>
            <span className="font-bold text-right">{natureLabel}</span>
          </div>
          <div className="flex justify-between gap-1">
            <span className="text-gray-600">Description:</span>
            <span className="text-right max-w-[58%] break-words">{description}</span>
          </div>
          <div className="flex justify-between gap-1">
            <span className="text-gray-600">Pièces:</span>
            <span className="text-right">{detail.nombrePieces}</span>
          </div>
          {detail.poidsKg != null && detail.poidsKg > 0 && (
            <div className="flex justify-between gap-1">
              <span className="text-gray-600">Poids:</span>
              <span className="text-right">{detail.poidsKg} kg</span>
            </div>
          )}
          <div className="flex justify-between gap-1 border-t border-dashed border-black/20 pt-0.5 mt-0.5">
            <span className="text-gray-600 font-bold">Montant fret:</span>
            <span className="font-bold text-right">
              {currency} {detail.montantFret.toLocaleString()}
            </span>
          </div>
          {detail.valeurMarchandise != null && detail.valeurMarchandise > 0 && (
            <div className="flex justify-between gap-1">
              <span className="text-gray-600">Valeur marchandise:</span>
              <span className="text-right">
                {currency} {detail.valeurMarchandise.toLocaleString()}
              </span>
            </div>
          )}
          {detail.pourcentagePercu != null && detail.pourcentagePercu > 0 && (
            <div className="flex justify-between gap-1">
              <span className="text-gray-600">Pourcentage perçu:</span>
              <span className="text-right">{detail.pourcentagePercu}%</span>
            </div>
          )}
        </div>

        <ReceiptPoweredByFooter companyLogoUrl={companyInfo?.logoUrl} />
      </div>

      <div className="space-y-2 print-hide">
        <div className="rounded-lg border p-3 space-y-2">
          <p className="text-[10px] uppercase tracking-wider font-semibold text-muted-foreground flex items-center gap-1.5">
            <PrinterIcon className="w-3.5 h-3.5" />
            Impression thermique (POS)
          </p>
          <div className="flex gap-2">
            <Button
              variant="secondary"
              size="sm"
              className="flex-1 cursor-pointer text-xs"
              onClick={() => handleThermalPrint("80mm")}
            >
              <PrinterIcon className="w-3.5 h-3.5 mr-1" />
              {posNative ? "POS" : "Imprimer"}
            </Button>
            <Button
              variant="secondary"
              size="sm"
              className="flex-1 cursor-pointer text-xs"
              onClick={() => handleThermalPrint("80mm")}
            >
              80mm
            </Button>
            <Button
              variant="secondary"
              size="sm"
              className="flex-1 cursor-pointer text-xs"
              onClick={() => handleThermalPrint("56mm")}
            >
              56mm
            </Button>
          </div>
        </div>
      </div>

      <div className="rounded-lg border p-3 space-y-2 print-hide">
        <p className="text-[10px] uppercase tracking-wider font-semibold text-muted-foreground flex items-center gap-1.5">
          <MessageCircleIcon className="w-3.5 h-3.5" />
          Notifier par WhatsApp
        </p>
        <div className="flex gap-2">
          <Button
            variant="secondary"
            size="sm"
            className="flex-1 cursor-pointer text-xs bg-[#25D366] hover:bg-[#1ebe57] text-white"
            onClick={() => handleWhatsAppShare("expediteur")}
          >
            Expéditeur
          </Button>
          <Button
            variant="secondary"
            size="sm"
            className="flex-1 cursor-pointer text-xs bg-[#25D366] hover:bg-[#1ebe57] text-white"
            onClick={() => handleWhatsAppShare("destinataire")}
          >
            Destinataire
          </Button>
        </div>
      </div>

      <div className="space-y-2 print-hide">
        {onNewShipment && (
          <Button onClick={onNewShipment} className="w-full cursor-pointer">
            <PlusIcon className="w-4 h-4 mr-1.5" /> Nouvel envoi
          </Button>
        )}
        {onBack && (
          <Button variant="secondary" onClick={onBack} className="w-full cursor-pointer">
            Retour
          </Button>
        )}
        {onDone && (
          <Button variant="ghost" onClick={onDone} className="w-full cursor-pointer text-xs">
            Terminé
          </Button>
        )}
      </div>
    </div>
  );
}
