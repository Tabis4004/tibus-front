import { Navigate, useParams } from "react-router-dom";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { resolvePrimaryGareStaffDashboardPath } from "@/lib/gare-role-routing.ts";

/** Redirige l’ancienne route /owner/gare-dashboard vers le dashboard du rôle gare. */
export default function GareDashboardRedirectPage() {
  const { lng } = useParams<{ lng: string }>();
  const appUser = useAppUser();
  const target = resolvePrimaryGareStaffDashboardPath(lng ?? "fr", appUser.roles);
  return <Navigate to={target} replace />;
}
