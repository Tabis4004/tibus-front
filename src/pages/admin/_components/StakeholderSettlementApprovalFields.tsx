import { useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";

export default function StakeholderSettlementApprovalFields({
  busy,
  onApprove,
  onReject,
}: {
  busy?: boolean;
  onApprove: (input: { approvalNote: string; proofFile: File }) => Promise<void>;
  onReject: () => Promise<void>;
}) {
  const { t } = useTranslation("admin");
  const fileRef = useRef<HTMLInputElement>(null);
  const [approvalNote, setApprovalNote] = useState("");
  const [proofFile, setProofFile] = useState<File | null>(null);

  return (
    <div className="w-full space-y-2 rounded-md border bg-muted/20 p-2">
      <div className="space-y-1">
        <Label className="text-xs">
          {t("stakeholder_commissions.approval_note_label", {
            defaultValue: "Base de validation (réf. virement, date, canal)",
          })}
        </Label>
        <Textarea
          className="min-h-[60px] text-sm"
          value={approvalNote}
          onChange={(e) => setApprovalNote(e.target.value)}
          placeholder={t("stakeholder_commissions.approval_note_placeholder", {
            defaultValue: "Ex. Virement OM 10/06/2026 ref. TX123456 — solde commissions mars",
          })}
        />
      </div>
      <div className="space-y-1">
        <Label className="text-xs">
          {t("stakeholder_commissions.payment_proof_label", {
            defaultValue: "Preuve de paiement (PDF, image)",
          })}
        </Label>
        <Input
          ref={fileRef}
          type="file"
          accept=".pdf,.jpg,.jpeg,.png,.webp,image/*,application/pdf"
          className="h-9 text-sm"
          onChange={(e) => setProofFile(e.target.files?.[0] ?? null)}
        />
      </div>
      <div className="flex flex-wrap gap-2">
        <Button
          size="sm"
          disabled={busy || !approvalNote.trim() || !proofFile}
          onClick={() => {
            if (!proofFile) return;
            void onApprove({ approvalNote: approvalNote.trim(), proofFile });
          }}
        >
          {t("stakeholder_commissions.approve_payment", { defaultValue: "Approuver" })}
        </Button>
        <Button size="sm" variant="outline" disabled={busy} onClick={() => void onReject()}>
          {t("stakeholder_commissions.reject_payment")}
        </Button>
      </div>
    </div>
  );
}
