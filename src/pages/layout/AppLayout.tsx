import { Outlet } from "react-router-dom";
import {
  Authenticated,
  AuthLoading,
  Unauthenticated,
} from "@/components/auth/AuthBoundary.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import AppHeader from "./_components/AppHeader.tsx";
import BottomNav from "./_components/BottomNav.tsx";

function ProfileLoading() {
  return (
    <div className="flex flex-col gap-4 p-6 max-w-2xl mx-auto mt-8">
      <Skeleton className="h-10 w-64" />
      <Skeleton className="h-4 w-full" />
      <Skeleton className="h-4 w-3/4" />
    </div>
  );
}

export default function AppLayout() {
  return (
    <div className="flex flex-col min-h-screen">
      <AuthLoading>
        <AppHeader />
        <main className="flex-1 pb-20 md:pb-0">
          <ProfileLoading />
        </main>
      </AuthLoading>
      <Unauthenticated>
        <Outlet />
      </Unauthenticated>
      <Authenticated>
        <AppHeader />
        <main className="flex-1 pb-20 md:pb-0">
          <Outlet />
        </main>
        <BottomNav />
      </Authenticated>
    </div>
  );
}
