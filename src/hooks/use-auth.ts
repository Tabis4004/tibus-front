import { useUser as useHerculesUser } from "@usehercules/auth/react";
import { useAuthContext } from "@/components/providers/auth-bridge";

export type AuthUser = {
  id: string;
  email?: string;
  name?: string;
  profileUrl?: string;
  profile: {
    name?: string;
    avatar?: string;
  };
};

export type AuthState = {
  isAuthenticated: boolean;
  isLoading: boolean;
  error: Error | null;
  signin: () => Promise<void>;
  signout: () => Promise<void>;
  user: AuthUser | null;
};

export function useAuth(): AuthState {
  return useAuthContext();
}

export function useUser() {
  const { user, isLoading, isAuthenticated } = useAuth();
  return { user, isLoading, isAuthenticated };
}

export { useHerculesUser };
