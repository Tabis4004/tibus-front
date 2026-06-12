/**
 * Sandbox admin UI — grants super_admin client-side for authenticated sessions only.
 * Does not bypass Supabase RLS; DB mutations still require real roles or RPC grants.
 *
 * Disable in production with VITE_ADMIN_SANDBOX=false at build time.
 */
export const ADMIN_SANDBOX_HARDCODED = false;

export function isAdminSandboxEnabled(): boolean {
  if (import.meta.env.VITE_ADMIN_SANDBOX === "false") return false;
  return ADMIN_SANDBOX_HARDCODED || import.meta.env.VITE_ADMIN_SANDBOX === "true";
}

export function resolveAdminSandboxRoles(
  roles: string[],
  isAuthenticated: boolean,
): { roles: string[]; isSandboxActive: boolean } {
  if (!isAuthenticated || !isAdminSandboxEnabled()) {
    return { roles, isSandboxActive: false };
  }

  if (roles.includes("super_admin")) {
    return { roles, isSandboxActive: false };
  }

  return {
    roles: [...roles, "super_admin"],
    isSandboxActive: true,
  };
}
