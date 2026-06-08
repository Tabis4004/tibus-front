import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { Checkbox } from "@/components/ui/checkbox.tsx";

type CguAcceptanceCheckboxProps = {
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
  id?: string;
  className?: string;
};

export default function CguAcceptanceCheckbox({
  checked,
  onCheckedChange,
  id = "accept-cgu",
  className,
}: CguAcceptanceCheckboxProps) {
  const { t } = useTranslation("common");
  const { lng } = useParams<{ lng: string }>();
  const cguPath = `/${lng ?? "fr"}/cgu`;

  return (
    <div className={className ?? "flex items-start gap-2.5"}>
      <Checkbox
        id={id}
        checked={checked}
        onCheckedChange={(value) => onCheckedChange(value === true)}
        className="mt-0.5"
      />
      <label htmlFor={id} className="text-sm leading-snug cursor-pointer">
        {t("auth.cgu_accept_prefix", { defaultValue: "J'accepte les" })}{" "}
        <Link
          to={cguPath}
          target="_blank"
          rel="noopener noreferrer"
          className="text-primary underline underline-offset-2 font-medium"
          onClick={(event) => event.stopPropagation()}
        >
          {t("auth.cgu_link", { defaultValue: "Conditions Générales d'Utilisation" })}
        </Link>
      </label>
    </div>
  );
}
