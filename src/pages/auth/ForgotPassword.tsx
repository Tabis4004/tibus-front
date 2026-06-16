import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card.tsx";
import { Spinner } from "@/components/ui/spinner.tsx";
import { recoveryEmailErrorMessage } from "@/lib/auth/recovery-email-error.ts";
import { ArrowLeftIcon, MailIcon } from "lucide-react";

export default function ForgotPasswordPage() {
  const { t } = useTranslation("common");
  const { lng } = useParams();
  const { requestPasswordReset } = useSupabaseAuth();
  const [email, setEmail] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [sent, setSent] = useState(false);

  const locale = lng ?? "fr";
  const loginPath = `/${locale}/auth/login`;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      const redirectTo = `${window.location.origin}/${locale}/auth/reset-password`;
      await requestPasswordReset(email, redirectTo);
      setSent(true);
      toast.success(
        t("auth.reset_email_sent", {
          defaultValue: "Si un compte existe pour cet email, un lien de réinitialisation a été envoyé.",
        }),
      );
    } catch (err) {
      console.error("[auth] resetPasswordForEmail failed", err);
      toast.error(recoveryEmailErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="flex min-h-svh items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>
            {t("auth.forgot_password", { defaultValue: "Mot de passe oublié" })}
          </CardTitle>
          <CardDescription>
            {t("auth.forgot_password_desc", {
              defaultValue:
                "Saisissez votre email. Vous recevrez un lien pour choisir un nouveau mot de passe.",
            })}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {sent ? (
            <div className="rounded-xl border border-primary/20 bg-primary/5 p-4 text-sm space-y-2">
              <div className="flex items-center gap-2 font-medium">
                <MailIcon className="h-4 w-4 text-primary" />
                {t("auth.reset_check_inbox", { defaultValue: "Vérifiez votre boîte mail" })}
              </div>
              <p className="text-muted-foreground text-xs">
                {t("auth.reset_email_hint", {
                  defaultValue:
                    "Le lien expire après un court délai. Pensez à vérifier les spams si vous ne voyez rien.",
                })}
              </p>
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="forgot-email">Email</Label>
                <Input
                  id="forgot-email"
                  type="email"
                  autoComplete="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                />
              </div>
              <Button type="submit" className="w-full" disabled={submitting}>
                {submitting ? (
                  <Spinner className="size-4" />
                ) : (
                  t("auth.send_reset_link", { defaultValue: "Envoyer le lien" })
                )}
              </Button>
            </form>
          )}

          <Button asChild variant="ghost" className="w-full">
            <Link to={loginPath}>
              <ArrowLeftIcon className="mr-2 h-4 w-4" />
              {t("auth.back_to_sign_in", { defaultValue: "Retour à la connexion" })}
            </Link>
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}
