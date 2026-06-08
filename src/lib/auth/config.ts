export type AuthProvider = "supabase" | "hercules";

export function getAuthProvider(): AuthProvider {
  const value = import.meta.env.VITE_AUTH_PROVIDER;
  return value === "hercules" ? "hercules" : "supabase";
}

export function isSupabaseAuth(): boolean {
  return getAuthProvider() === "supabase";
}
