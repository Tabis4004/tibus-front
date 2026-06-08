import { Outlet, useNavigate, useParams } from "react-router-dom";
import { useEffect } from "react";
import { useQuery } from "convex/react";
import { api } from "@/convex/_generated/api.js";
import {
  Authenticated,
  AuthLoading,
  Unauthenticated,
} from "@/components/auth/AuthBoundary.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import AppHeader from "./_components/AppHeader.tsx";
import BottomNav from "./_components/BottomNav.tsx";
import { isSupabaseAuth } from "@/lib/auth/config";
import { useAppUser } from "@/hooks/use-app-user.ts";

function ProfileLoading() {
  return (
    <div className="flex flex-col gap-4 p-6 max-w-2xl mx-auto mt-8">
      <Skeleton className="h-10 w-64" />
      <Skeleton className="h-4 w-full" />
      <Skeleton className="h-4 w-3/4" />
    </div>
  );
}

function SupabaseProfileGate({ children }: { children: React.ReactNode }) {
  const navigate = useNavigate();
  const { lng } = useParams();
  const appUser = useAppUser();

  useEffect(() => {
    if (appUser.isReady && !appUser.profileCompleted) {
      navigate(`/${lng ?? "en"}/complete-profile`, { replace: true });
    }
  }, [appUser.isReady, appUser.profileCompleted, navigate, lng]);

  if (appUser.isLoading || !appUser.isReady) {
    return <ProfileLoading />;
  }

  if (!appUser.profileCompleted) {
    return null;
  }

  return <>{children}</>;
}

function ConvexProfileGate({ children }: { children: React.ReactNode }) {
  const navigate = useNavigate();
  const { lng } = useParams();
  const currentUser = useQuery(api.users.getCurrentUser);

  useEffect(() => {
    if (currentUser && !currentUser.profileCompleted) {
      navigate(`/${lng ?? "en"}/complete-profile`, { replace: true });
    }
  }, [currentUser, navigate, lng]);

  if (currentUser === undefined) {
    return <ProfileLoading />;
  }

  if (!currentUser?.profileCompleted) {
    return null;
  }

  return <>{children}</>;
}

function ProfileGate({ children }: { children: React.ReactNode }) {
  if (isSupabaseAuth()) {
    return <SupabaseProfileGate>{children}</SupabaseProfileGate>;
  }

  return <ConvexProfileGate>{children}</ConvexProfileGate>;
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
