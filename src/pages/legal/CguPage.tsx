import { useTranslation } from "react-i18next";
import LegalPageView from "./LegalPageView.tsx";

export default function CguPage() {
  const { t } = useTranslation("common");
  return (
    <LegalPageView
      slug="cgu"
      fallbackTitle={t("auth.cgu_link", { defaultValue: "Conditions Générales d'Utilisation" })}
    />
  );
}
