import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import type { Session, User } from "@supabase/supabase-js";
import { ensureUserProfile } from "@/lib/auth/ensure-profile";
import { isSupabaseAuth } from "@/lib/auth/config";
import { supabase } from "@/lib/supabase";

type SupabaseSignUpResult = {
  user: User | null;
  session: Session | null;
  appUserId: string | null;
  requiresConfirmation: boolean;
};

type SupabaseAuthContextValue = {
  session: Session | null;
  user: User | null;
  appUserId: string | null;
  isLoading: boolean;
  isBootstrapping: boolean;
  error: Error | null;
  signInWithPassword: (email: string, password: string) => Promise<void>;
  signUpWithPassword: (
    email: string,
    password: string,
  ) => Promise<SupabaseSignUpResult>;
  signOut: () => Promise<void>;
};

const SupabaseAuthContext = createContext<SupabaseAuthContextValue | null>(null);

const noop = async () => {
  throw new Error("Supabase Auth désactivé (VITE_AUTH_PROVIDER=hercules)");
};

export function SupabaseAuthProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  const enabled = isSupabaseAuth();
  const [session, setSession] = useState<Session | null>(null);
  const [appUserId, setAppUserId] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(enabled);
  const [isBootstrapping, setIsBootstrapping] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const bootstrapProfile = useCallback(async (authUser: User | null) => {
    if (!authUser || !enabled) {
      setAppUserId(null);
      return null;
    }

    setIsBootstrapping(true);
    setError(null);
    try {
      const id = await ensureUserProfile(authUser);
      setAppUserId(id);
      return id;
    } catch (err) {
      setError(err instanceof Error ? err : new Error("Profil utilisateur"));
      setAppUserId(null);
      return null;
    } finally {
      setIsBootstrapping(false);
    }
  }, [enabled]);

  useEffect(() => {
    if (!enabled) {
      setIsLoading(false);
      return;
    }

    supabase.auth.getSession().then(async ({ data, error }) => {
      if (
        error?.message &&
        (error.message.toLowerCase().includes("refresh token") ||
          error.message.toLowerCase().includes("invalid credentials"))
      ) {
        await supabase.auth.signOut();
        setSession(null);
        setIsLoading(false);
        return;
      }
      setSession(data.session);
      setIsLoading(false);
      void bootstrapProfile(data.session?.user ?? null);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      setIsLoading(false);
      void bootstrapProfile(nextSession?.user ?? null);
    });

    return () => subscription.unsubscribe();
  }, [bootstrapProfile, enabled]);

  const signInWithPassword = useCallback(async (email: string, password: string) => {
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    if (signInError) throw signInError;
  }, []);

  const signUpWithPassword = useCallback(async (email: string, password: string) => {
    const { data, error: signUpError } = await supabase.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`,
      },
    });
    if (signUpError) throw signUpError;

    const nextAppUserId =
      data.user && data.session ? await bootstrapProfile(data.user) : null;

    return {
      user: data.user,
      session: data.session,
      appUserId: nextAppUserId,
      requiresConfirmation: !data.session,
    };
  }, [bootstrapProfile]);

  const signOut = useCallback(async () => {
    setAppUserId(null);
    await supabase.auth.signOut();
  }, []);

  const value = useMemo<SupabaseAuthContextValue>(
    () => ({
      session: enabled ? session : null,
      user: enabled ? (session?.user ?? null) : null,
      appUserId: enabled ? appUserId : null,
      isLoading: enabled ? isLoading : false,
      isBootstrapping: enabled ? isBootstrapping : false,
      error: enabled ? error : null,
      signInWithPassword: enabled ? signInWithPassword : noop,
      signUpWithPassword: enabled ? signUpWithPassword : noop,
      signOut: enabled ? signOut : async () => {},
    }),
    [
      enabled,
      session,
      appUserId,
      isLoading,
      isBootstrapping,
      error,
      signInWithPassword,
      signUpWithPassword,
      signOut,
    ],
  );

  return (
    <SupabaseAuthContext.Provider value={value}>
      {children}
    </SupabaseAuthContext.Provider>
  );
}

export function useSupabaseAuth() {
  const context = useContext(SupabaseAuthContext);
  if (!context) {
    throw new Error("useSupabaseAuth must be used within SupabaseAuthProvider");
  }
  return context;
}
