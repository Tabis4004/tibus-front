import { useCallback, useEffect, useState } from "react";
import SellerTicketReceiptPanel from "@/components/seller/SellerTicketReceiptPanel.tsx";
import ColisReceiptPanel from "@/components/seller/ColisReceiptPanel.tsx";
import {
  getSellerCompanyReceiptInfoSupabase,
  type SellerCompanyReceiptInfo,
} from "@/lib/supabase/seller-counter";
import { buildCounterTicketReprintInput } from "@/lib/supabase/ticket-reprint";
import { getColisAutonomeDetailSupabase, type ColisAutonomeDetail } from "@/lib/supabase/colis-autonomes.ts";
import type { CompanyTicketSaleRow } from "@/lib/supabase/cancellation";

export function useCompanyTicketReprint(companyId: string, companyName: string) {
  const [reprintInput, setReprintInput] = useState<Awaited<
    ReturnType<typeof buildCounterTicketReprintInput>
  > | null>(null);
  const [colisReprintDetail, setColisReprintDetail] = useState<ColisAutonomeDetail | null>(null);
  const [companyInfo, setCompanyInfo] = useState<SellerCompanyReceiptInfo | null>(null);

  useEffect(() => {
    if (!companyId?.trim()) return;
    let cancelled = false;
    void getSellerCompanyReceiptInfoSupabase(companyId)
      .then((info) => {
        if (!cancelled) setCompanyInfo(info);
      })
      .catch(() => {
        if (!cancelled) setCompanyInfo(null);
      });
    return () => {
      cancelled = true;
    };
  }, [companyId]);

  const clearReprint = useCallback(() => {
    setReprintInput(null);
    setColisReprintDetail(null);
  }, []);

  const onReprint = useCallback(
    async (row: CompanyTicketSaleRow) => {
      if (row.reference.toUpperCase().startsWith("CL-")) {
        const detail = await getColisAutonomeDetailSupabase(row.bookingId);
        if (!detail) throw new Error("Colis introuvable");
        setColisReprintDetail(detail);
        setReprintInput(null);
        return;
      }
      const input = await buildCounterTicketReprintInput(row, companyName);
      setColisReprintDetail(null);
      setReprintInput(input);
    },
    [companyName],
  );

  const reprintView =
    colisReprintDetail != null ? (
      <ColisReceiptPanel
        detail={colisReprintDetail}
        companyInfo={companyInfo ?? undefined}
        showSuccessHeader={false}
        onBack={clearReprint}
        onDone={clearReprint}
      />
    ) : reprintInput != null ? (
      <SellerTicketReceiptPanel
        input={reprintInput}
        companyInfo={companyInfo ?? undefined}
        showSuccessHeader={false}
        onBack={clearReprint}
        onDone={clearReprint}
      />
    ) : null;

  return {
    onReprint,
    reprintView,
    isReprinting: reprintInput != null || colisReprintDetail != null,
  };
}
