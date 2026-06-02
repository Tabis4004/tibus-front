import { Outlet, useNavigate, useParams } from "react-router-dom";
import { useEffect } from "react";
import { Authenticated, AuthLoading, Unauthenticated, useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import { SignInButton } from "@/components/ui/signin.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import AppHeader from "./_components/AppHeader.tsx";
import BottomNav from "./_components/BottomNav.tsx";
import { useTranslation } from "react-i18next";

function ProfileGate({ children }: { children: React.ReactNode }) {
  const navigate = useNavigate();
  const { lng } = useParams();
  const currentUser = useQuery(api.users.getCurrentUser);

  useEffect(() => {
    if (currentUser && !currentUser.profileCompleted) {
      navigate(`/${lng ?? "en"}/complete-profile`, { replace: true });
    }
  }, [currentUser, navigate, lng]);

  // Still loading user
  if (currentUser === undefined) {
    return (
      <div className="flex flex-col gap-4 p-6 max-w-2xl mx-auto mt-8">
        <Skeleton className="h-10 w-64" />
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-3/4" />
      </div>
    );
  }

  // Profile not complete — redirecting
  if (!currentUser?.profileCompleted) {
    return null;
  }

  return <>{children}</>;
}

export default function AppLayout() {
  const { t } = useTranslation("common");

  return (
    <div className="flex flex-col min-h-screen">
      <AuthLoading>
        <AppHeader />
        <main className="flex-1 pb-20 md:pb-0">
          <div className="flex flex-col gap-4 p-6 max-w-2xl mx-auto mt-8">
            <Skeleton className="h-10 w-64" />
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-3/4" />
          </div>
        </main>
      </AuthLoading>
      <Unauthenticated>
        {/* Let Index page render its own landing page layout */}
        <Outlet />
      </Unauthenticated>
      <Authenticated>
        <AppHeader />
        <main className="flex-1 pb-20 md:pb-0">
          <ProfileGate>
            <Outlet />
          </ProfileGate>
        </main>
        <BottomNav />
      </Authenticated>
    </div>
  );
}
