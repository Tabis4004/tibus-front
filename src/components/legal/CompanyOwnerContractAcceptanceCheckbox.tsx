import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { Checkbox } from "@/components/ui/checkbox.tsx";
import { COMPANY_OWNER_CONTRACT_PATH } from "@/lib/supabase/legal-pages.ts";

type CompanyOwnerContractAcceptanceCheckboxProps = {
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
  countryId?: string | null;
  id?: string;
  className?: string;
};

export default function CompanyOwnerContractAcceptanceCheckbox({
  checked,
  onCheckedChange,
  countryId,
  id = "accept-company-owner-contract",
  className,
}: CompanyOwnerContractAcceptanceCheckboxProps) {
  const { t } = useTranslation("owner");
  const { lng } = useParams<{ lng: string }>();
  const query = countryId ? `?countryId=${countryId}` : "";
  const contractPath = `/${lng ?? "fr"}/${COMPANY_OWNER_CONTRACT_PATH}${query}`;

  return (
    <div className={className ?? "flex items-start gap-2.5 rounded-lg border p-3 bg-muted/30"}>
      <Checkbox
        id={id}
        checked={checked}
        onCheckedChange={(value) => onCheckedChange(value === true)}
        className="mt-0.5"
      />
      <label htmlFor={id} className="text-sm leading-snug cursor-pointer">
        {t("company_owner_contract.accept_prefix", {
          defaultValue: "J'accepte le",
        })}{" "}
        <Link
          to={contractPath}
          target="_blank"
          rel="noopener noreferrer"
          className="text-primary underline underline-offset-2 font-medium"
          onClick={(event) => event.stopPropagation()}
        >
          {t("company_owner_contract.link", {
            defaultValue: "contrat propriétaire de compagnie",
          })}
        </Link>
        {t("company_owner_contract.annex_short", {
          defaultValue: " (incluant l'annexe offre technique)",
        })}
        <span className="text-destructive"> *</span>
      </label>
    </div>
  );
}
