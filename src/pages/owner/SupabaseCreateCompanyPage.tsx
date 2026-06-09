import { OwnerCompanyProvider } from "@/hooks/use-owner-company.tsx";
import SupabaseCompanySettings from "./SupabaseCompanySettings.tsx";

export default function SupabaseCreateCompanyPage() {
  return (
    <OwnerCompanyProvider>
      <SupabaseCompanySettings />
    </OwnerCompanyProvider>
  );
}
