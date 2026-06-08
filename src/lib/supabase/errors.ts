type ErrorLike = {
  message?: string;
  details?: string;
  hint?: string;
  code?: string;
};

/** Extrait un message lisible depuis une erreur Supabase/PostgREST ou inconnue. */
export function supabaseErrorMessage(
  err: unknown,
  fallback = "Erreur inconnue",
): string {
  if (!err) return fallback;

  if (typeof err === "string" && err.trim()) return err.trim();

  if (err instanceof Error && err.message.trim()) {
    return err.message.trim();
  }

  if (typeof err === "object" && err !== null) {
    const row = err as ErrorLike;
    const message = row.message?.trim();
    if (message) {
      const details = row.details?.trim();
      if (details && details !== message) {
        return `${message} — ${details}`;
      }
      return message;
    }
  }

  return fallback;
}

export function throwSupabaseError(err: unknown, fallback?: string): never {
  throw new Error(supabaseErrorMessage(err, fallback));
}
