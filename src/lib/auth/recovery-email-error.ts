/** Message utilisateur pour les échecs d'envoi du mail de réinitialisation Supabase Auth. */
export function recoveryEmailErrorMessage(err: unknown): string {
  const message =
    err instanceof Error
      ? err.message
      : typeof err === "object" && err !== null && "message" in err
        ? String((err as { message: unknown }).message)
        : String(err);

  if (/error sending recovery email/i.test(message)) {
    return [
      "Supabase n'a pas pu envoyer l'email de réinitialisation.",
      "Vérifiez : SMTP custom (Authentication → Emails → SMTP Settings),",
      "URLs de redirection autorisées, et les logs Auth du projet.",
    ].join(" ");
  }

  if (/email address not authorized/i.test(message)) {
    return [
      "Cette adresse n'est pas autorisée avec l'email intégré Supabase.",
      "Configurez un SMTP custom ou ajoutez l'adresse à l'équipe de l'organisation Supabase.",
    ].join(" ");
  }

  if (/rate limit|too many requests/i.test(message)) {
    return "Limite d'envoi d'emails atteinte. Réessayez plus tard ou configurez un SMTP custom.";
  }

  return message.trim() || "Erreur inconnue";
}
