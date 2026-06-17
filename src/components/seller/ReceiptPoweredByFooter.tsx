import { RECEIPT_POWERED_BY_LINE } from "@/lib/receipt-branding.ts";

export default function ReceiptPoweredByFooter({
  companyLogoUrl,
}: {
  companyLogoUrl?: string | null;
}) {
  return (
    <div className="receipt-footer border-t border-dashed border-black/30 pt-2 mt-2 flex items-center justify-center gap-2 text-[9px] text-gray-700">
      {companyLogoUrl ? (
        <img
          src={companyLogoUrl}
          alt="Logo compagnie"
          className="h-5 max-w-[72px] object-contain shrink-0"
        />
      ) : null}
      <span className="font-bold tracking-wide text-center leading-tight">{RECEIPT_POWERED_BY_LINE}</span>
    </div>
  );
}
