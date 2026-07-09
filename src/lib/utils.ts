import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

// Extrait un message d'erreur affichable à partir de n'importe quoi
// (Error, PostgrestError-like plain object, string, etc.). Utilisé dans les
// catch des formulaires pour ne jamais retomber sur un message générique
// quand l'API a en fait renvoyé une raison précise (ex. contrainte/trigger
// Postgres) — un objet non-Error passerait sinon inaperçu avec un simple
// `err instanceof Error` check.
export function errorMessage(err: unknown, fallback: string): string {
  if (err instanceof Error && err.message) return err.message;
  if (typeof err === "string" && err) return err;
  if (err && typeof err === "object" && "message" in err) {
    const message = (err as { message?: unknown }).message;
    if (typeof message === "string" && message) return message;
  }
  return fallback;
}
