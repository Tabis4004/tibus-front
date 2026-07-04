import { useTranslation } from "react-i18next";
import LegalPageView from "./LegalPageView.tsx";

export default function PrivacyPolicyPage() {
  const { t } = useTranslation("common");
  return (
    <LegalPageView
      slug="politique-confidentialite"
      fallbackTitle={t("auth.privacy_link", { defaultValue: "Politique de Confidentialité" })}
    />
  );
}
