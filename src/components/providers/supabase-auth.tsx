import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import type { Session, User } from "@supabase/supabase-js";
import { ensureUserProfile } from "@/lib/auth/ensure-profile";
import { applySignupProfile } from "@/lib/auth/complete-profile";
import { isSupabaseAuth } from "@/lib/auth/config";
import { supabase } from "@/lib/supabase";

type SupabaseSignUpResult = {
  user: User | null;
  session: Session | null;
  appUserId: string | null;
  requiresConfirmation: boolean;
};

type SignUpProfile = {
  fullName: string;
  phone: string;
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
    profile?: SignUpProfile,
  ) => Promise<SupabaseSignUpResult>;
  requestPasswordReset: (email: string, redirectTo: string) => Promise<void>;
  updatePassword: (password: string) => Promise<void>;
  signInWithPhoneOtp: (phone: string) => Promise<void>;
  verifyPhoneOtp: (phone: string, token: string) => Promise<void>;
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
  const lastBootstrappedAuthIdRef = useRef<string | null>(null);

  const bootstrapProfile = useCallback(async (authUser: User | null) => {
    if (!authUser || !enabled) {
      lastBootstrappedAuthIdRef.current = null;
      setAppUserId(null);
      return null;
    }

    if (lastBootstrappedAuthIdRef.current === authUser.id) {
      return null;
    }

    setIsBootstrapping(true);
    setError(null);
    try {
      const id = await ensureUserProfile(authUser);
      lastBootstrappedAuthIdRef.current = authUser.id;
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
    } = supabase.auth.onAuthStateChange((event, nextSession) => {
      setSession(nextSession);
      setIsLoading(false);

      if (event === "TOKEN_REFRESHED") {
        return;
      }

      if (event === "SIGNED_OUT" || !nextSession?.user) {
        lastBootstrappedAuthIdRef.current = null;
        setAppUserId(null);
        return;
      }

      void bootstrapProfile(nextSession.user);
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

  const signUpWithPassword = useCallback(async (
    email: string,
    password: string,
    profile?: SignUpProfile,
  ) => {
    const { data, error: signUpError } = await supabase.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`,
        data: profile
          ? {
              full_name: profile.fullName.trim(),
              phone: profile.phone.trim(),
            }
          : undefined,
      },
    });
    if (signUpError) throw signUpError;

    const nextAppUserId =
      data.user && data.session ? await bootstrapProfile(data.user) : null;

    if (nextAppUserId && profile) {
      await applySignupProfile({
        userId: nextAppUserId,
        email,
        fullName: profile.fullName,
        phone: profile.phone,
      });
    }

    return {
      user: data.user,
      session: data.session,
      appUserId: nextAppUserId,
      requiresConfirmation: !data.session,
    };
  }, [bootstrapProfile]);

  const requestPasswordReset = useCallback(async (email: string, redirectTo: string) => {
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo,
    });
    if (resetError) throw resetError;
  }, []);

  const updatePassword = useCallback(async (password: string) => {
    const { error: updateError } = await supabase.auth.updateUser({ password });
    if (updateError) throw updateError;
  }, []);

  const signInWithPhoneOtp = useCallback(async (phone: string) => {
    const { error: otpError } = await supabase.auth.signInWithOtp({
      phone,
      options: { channel: "sms" },
    });
    if (otpError) throw otpError;
  }, []);

  const verifyPhoneOtp = useCallback(async (phone: string, token: string) => {
    const { error: verifyError } = await supabase.auth.verifyOtp({
      phone,
      token,
      type: "sms",
    });
    if (verifyError) throw verifyError;
  }, []);

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
      requestPasswordReset: enabled ? requestPasswordReset : noop,
      updatePassword: enabled ? updatePassword : noop,
      signInWithPhoneOtp: enabled ? signInWithPhoneOtp : noop,
      verifyPhoneOtp: enabled ? verifyPhoneOtp : noop,
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
      requestPasswordReset,
      updatePassword,
      signInWithPhoneOtp,
      verifyPhoneOtp,
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
