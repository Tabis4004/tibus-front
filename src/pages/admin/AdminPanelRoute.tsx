import { lazy, Suspense } from "react";
import { isSupabaseAuth } from "@/lib/auth/config";
import { Skeleton } from "@/components/ui/skeleton.tsx";

const SupabaseAdminPanel = lazy(() => import("./SupabaseAdminPanel.tsx"));
const ConvexAdminPanel = lazy(() => import("./AdminPanel.tsx"));

function AdminPanelFallback() {
  return (
    <div className="max-w-6xl mx-auto px-4 py-8 space-y-4">
      <Skeleton className="h-10 w-64" />
      <Skeleton className="h-40 w-full" />
    </div>
  );
}

export default function AdminPanelRoute() {
  const Panel = isSupabaseAuth() ? SupabaseAdminPanel : ConvexAdminPanel;
  return (
    <Suspense fallback={<AdminPanelFallback />}>
      <Panel />
    </Suspense>
  );
}
