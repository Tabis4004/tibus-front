import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  type ReactNode,
} from "react";
import { useNavigate } from "react-router-dom";
import {
  useAuth as useHerculesAuth,
} from "@usehercules/auth/react";
import { isSupabaseAuth } from "@/lib/auth/config";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { SAVED_OR_DEFAULT_LOCALE } from "@/i18n";
import type { AuthState, AuthUser } from "@/hooks/use-auth";

const AuthContext = createContext<AuthState | null>(null);

function useSupabaseAuthBridgeValue(): AuthState {
  const navigate = useNavigate();
  const supabase = useSupabaseAuth();

  const signin = useCallback(async () => {
    navigate(`/${SAVED_OR_DEFAULT_LOCALE}/auth/login`);
  }, [navigate]);

  const signout = useCallback(async () => {
    await supabase.signOut();
  }, [supabase]);

  const authUser = supabase.user;
  const displayName =
    (authUser?.user_metadata?.full_name as string | undefined) ??
    authUser?.email ??
    undefined;
  const avatarUrl = authUser?.user_metadata?.avatar_url as string | undefined;

  const user: AuthUser | null = authUser
    ? {
        id: authUser.id,
        email: authUser.email,
        name: displayName,
        profileUrl: avatarUrl,
        profile: {
          name: displayName,
          avatar: avatarUrl,
        },
      }
    : null;

  return useMemo(
    () => ({
      isAuthenticated: !!supabase.session,
      isLoading: supabase.isLoading,
      error: supabase.error,
      signin,
      signout,
      user,
    }),
    [
      supabase.session,
      supabase.isLoading,
      supabase.error,
      signin,
      signout,
      user,
    ],
  );
}

function useHerculesAuthBridgeValue(): AuthState {
  const hercules = useHerculesAuth();

  const signin = useCallback(async () => {
    await hercules.signin();
  }, [hercules]);

  const signout = useCallback(async () => {
    await hercules.signout();
  }, [hercules]);

  const hUser = hercules.user;
  const user: AuthUser | null = hUser
    ? {
        id: (hUser as { sub?: string }).sub ?? "",
        email: (hUser as { email?: string }).email,
        name: hUser.profile?.name,
        profileUrl: (hUser as { profileUrl?: string }).profileUrl,
        profile: {
          name: hUser.profile?.name,
          avatar:
            typeof hUser.profile?.avatar === "string"
              ? hUser.profile.avatar
              : undefined,
        },
      }
    : null;

  return useMemo(
    () => ({
      isAuthenticated: hercules.isAuthenticated,
      isLoading: hercules.isLoading,
      error: hercules.error ? new Error(hercules.error.message) : null,
      signin,
      signout,
      user,
    }),
    [
      hercules.isAuthenticated,
      hercules.isLoading,
      hercules.error,
      signin,
      signout,
      user,
    ],
  );
}

function SupabaseAuthBridgeProvider({ children }: { children: ReactNode }) {
  const value = useSupabaseAuthBridgeValue();
  return (
    <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
  );
}

function HerculesAuthBridgeProvider({ children }: { children: ReactNode }) {
  const value = useHerculesAuthBridgeValue();
  return (
    <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
  );
}

export function AuthBridgeProvider({ children }: { children: ReactNode }) {
  if (isSupabaseAuth()) {
    return <SupabaseAuthBridgeProvider>{children}</SupabaseAuthBridgeProvider>;
  }
  return <HerculesAuthBridgeProvider>{children}</HerculesAuthBridgeProvider>;
}

export function useAuthContext(): AuthState {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used within AuthBridgeProvider");
  }
  return context;
}
