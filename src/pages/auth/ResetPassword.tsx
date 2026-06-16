import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { supabase } from "@/lib/supabase";
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
import { ArrowLeftIcon } from "lucide-react";

export default function ResetPasswordPage() {
  const { t } = useTranslation("common");
  const { lng } = useParams();
  const navigate = useNavigate();
  const { updatePassword } = useSupabaseAuth();
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [recoveryReady, setRecoveryReady] = useState(false);
  const [checkingLink, setCheckingLink] = useState(true);

  const locale = lng ?? "fr";
  const loginPath = `/${locale}/auth/login`;
  const forgotPath = `/${locale}/auth/forgot-password`;

  useEffect(() => {
    let cancelled = false;

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, session) => {
      if (cancelled) return;
      if (event === "PASSWORD_RECOVERY" || session) {
        setRecoveryReady(true);
        setCheckingLink(false);
      }
    });

    void supabase.auth.getSession().then(({ data }) => {
      if (cancelled) return;
      if (data.session) {
        setRecoveryReady(true);
      }
      setCheckingLink(false);
    });

    return () => {
      cancelled = true;
      subscription.unsubscribe();
    };
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (password.length < 6) {
      toast.error(
        t("auth.password_min_length", {
          defaultValue: "Le mot de passe doit contenir au moins 6 caractères.",
        }),
      );
      return;
    }
    if (password !== confirmPassword) {
      toast.error(
        t("auth.password_mismatch", {
          defaultValue: "Les mots de passe ne correspondent pas.",
        }),
      );
      return;
    }

    setSubmitting(true);
    try {
      await updatePassword(password);
      toast.success(
        t("auth.password_updated", {
          defaultValue: "Mot de passe mis à jour. Vous pouvez vous connecter.",
        }),
      );
      await supabase.auth.signOut();
      navigate(loginPath, { replace: true });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("errors.generic"));
    } finally {
      setSubmitting(false);
    }
  };

  if (checkingLink) {
    return (
      <div className="flex h-svh items-center justify-center">
        <Spinner className="size-8" />
      </div>
    );
  }

  return (
    <div className="flex min-h-svh items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>
            {t("auth.reset_password", { defaultValue: "Nouveau mot de passe" })}
          </CardTitle>
          <CardDescription>
            {t("auth.reset_password_desc", {
              defaultValue: "Choisissez un nouveau mot de passe pour votre compte Tibus.",
            })}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {!recoveryReady ? (
            <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm space-y-3">
              <p className="font-medium text-destructive">
                {t("auth.reset_link_invalid", {
                  defaultValue: "Lien invalide ou expiré.",
                })}
              </p>
              <p className="text-muted-foreground text-xs">
                {t("auth.reset_link_invalid_hint", {
                  defaultValue: "Demandez un nouveau lien de réinitialisation.",
                })}
              </p>
              <Button asChild variant="outline" className="w-full">
                <Link to={forgotPath}>
                  {t("auth.forgot_password", { defaultValue: "Mot de passe oublié" })}
                </Link>
              </Button>
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="reset-password">
                  {t("auth.new_password", { defaultValue: "Nouveau mot de passe" })}
                </Label>
                <Input
                  id="reset-password"
                  type="password"
                  autoComplete="new-password"
                  minLength={6}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="reset-password-confirm">
                  {t("auth.confirm_password", { defaultValue: "Confirmer le mot de passe" })}
                </Label>
                <Input
                  id="reset-password-confirm"
                  type="password"
                  autoComplete="new-password"
                  minLength={6}
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  required
                />
              </div>
              <Button type="submit" className="w-full" disabled={submitting}>
                {submitting ? (
                  <Spinner className="size-4" />
                ) : (
                  t("auth.save_password", { defaultValue: "Enregistrer" })
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
