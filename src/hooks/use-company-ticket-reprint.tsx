import { useCallback, useEffect, useState } from "react";
import SellerTicketReceiptPanel from "@/components/seller/SellerTicketReceiptPanel.tsx";
import {
  getSellerCompanyReceiptInfoSupabase,
  type SellerCompanyReceiptInfo,
} from "@/lib/supabase/seller-counter";
import { buildCounterTicketReprintInput } from "@/lib/supabase/ticket-reprint";
import type { CompanyTicketSaleRow } from "@/lib/supabase/cancellation";

export function useCompanyTicketReprint(companyId: string, companyName: string) {
  const [reprintInput, setReprintInput] = useState<Awaited<
    ReturnType<typeof buildCounterTicketReprintInput>
  > | null>(null);
  const [companyInfo, setCompanyInfo] = useState<SellerCompanyReceiptInfo | null>(null);

  useEffect(() => {
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

  const onReprint = useCallback(
    async (row: CompanyTicketSaleRow) => {
      const input = await buildCounterTicketReprintInput(row, companyName);
      setReprintInput(input);
    },
    [companyName],
  );

  const clearReprint = useCallback(() => setReprintInput(null), []);

  const reprintView =
    reprintInput != null ? (
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
    isReprinting: reprintInput != null,
  };
}
