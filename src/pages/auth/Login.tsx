import { useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import { refreshAppUserAsync } from "@/hooks/use-app-user.ts";
import {
  fetchUserRoleNames,
  resolveDashboardPath,
} from "@/lib/auth/role-routing.ts";
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
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs.tsx";
import { Spinner } from "@/components/ui/spinner.tsx";
import { StoreIcon } from "lucide-react";
import CguAcceptanceCheckbox from "@/components/legal/CguAcceptanceCheckbox.tsx";

export default function LoginPage() {
  const { t } = useTranslation("common");
  const { lng } = useParams();
  const navigate = useNavigate();
  const { signInWithPassword, signUpWithPassword, isLoading } = useSupabaseAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [fullName, setFullName] = useState("");
  const [phone, setPhone] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [acceptedCgu, setAcceptedCgu] = useState(false);

  const locale = lng ?? "fr";
  const home = `/${locale}`;

  const redirectAfterAuth = async () => {
    try {
      await refreshAppUserAsync();
    } catch {
      // Profile refresh may lag; fall back to role lookup or home.
    }

    const { data: authData } = await supabase.auth.getUser();
    const userId = authData.user?.id;
    if (!userId) {
      navigate(home, { replace: true });
      return;
    }

    try {
      const roles = await fetchUserRoleNames(userId);
      navigate(resolveDashboardPath(locale, roles), { replace: true });
    } catch {
      navigate(home, { replace: true });
    }
  };

  const handleSignIn = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!acceptedCgu) {
      toast.error(t("auth.cgu_required", { defaultValue: "Veuillez accepter les CGU pour continuer." }));
      return;
    }
    setSubmitting(true);
    try {
      await signInWithPassword(email, password);
      toast.success(t("auth.sign_in_success", { defaultValue: "Connexion réussie" }));
      await redirectAfterAuth();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("errors.generic"));
    } finally {
      setSubmitting(false);
    }
  };

  const handleSignUp = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!acceptedCgu) {
      toast.error(t("auth.cgu_required", { defaultValue: "Veuillez accepter les CGU pour continuer." }));
      return;
    }
    if (!fullName.trim()) {
      toast.error(t("profile.full_name", { defaultValue: "Nom complet" }) + " requis");
      return;
    }
    const phoneDigits = phone.replace(/\D/g, "");
    if (phoneDigits.length < 9) {
      toast.error(t("labels.phone", { defaultValue: "Téléphone" }) + " requis (9 chiffres minimum)");
      return;
    }
    setSubmitting(true);
    try {
      const result = await signUpWithPassword(email, password, {
        fullName: fullName.trim(),
        phone: phone.trim(),
      });
      toast.success(
        result.requiresConfirmation
          ? t("auth.sign_up_success", {
              defaultValue: "Compte créé. Vérifiez votre email si la confirmation est activée.",
            })
          : t("auth.sign_up_ready", {
              defaultValue: "Compte créé. Bienvenue sur Tibus !",
            }),
      );
      if (result.requiresConfirmation) {
        navigate(home, { replace: true });
      } else {
        await redirectAfterAuth();
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("errors.generic"));
    } finally {
      setSubmitting(false);
    }
  };

  if (isLoading) {
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
          <CardTitle>Tibus</CardTitle>
          <CardDescription>
            {t("auth.supabase_migration_hint", {
              defaultValue: "Authentification Supabase (migration en cours)",
            })}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Tabs defaultValue="signin">
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="signin">
                {t("auth.sign_in", { defaultValue: "Connexion" })}
              </TabsTrigger>
              <TabsTrigger value="signup">
                {t("auth.sign_up", { defaultValue: "Inscription" })}
              </TabsTrigger>
            </TabsList>

            <TabsContent value="signin">
              <form onSubmit={handleSignIn} className="space-y-4 pt-4">
                <div className="space-y-2">
                  <Label htmlFor="signin-email">Email</Label>
                  <Input
                    id="signin-email"
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                  />
                </div>
                <div className="space-y-2">
                  <div className="flex items-center justify-between gap-2">
                    <Label htmlFor="signin-password">Mot de passe</Label>
                    <Link
                      to={`/${locale}/auth/forgot-password`}
                      className="text-xs text-primary hover:underline"
                    >
                      {t("auth.forgot_password", { defaultValue: "Mot de passe oublié ?" })}
                    </Link>
                  </div>
                  <Input
                    id="signin-password"
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                  />
                </div>
                <CguAcceptanceCheckbox
                  id="signin-cgu"
                  checked={acceptedCgu}
                  onCheckedChange={setAcceptedCgu}
                />
                <Button type="submit" className="w-full" disabled={submitting || !acceptedCgu}>
                  {submitting ? <Spinner className="size-4" /> : t("auth.sign_in")}
                </Button>
              </form>
            </TabsContent>

            <TabsContent value="signup">
              <form onSubmit={handleSignUp} className="space-y-4 pt-4">
                <p className="text-sm text-muted-foreground">
                  {t("auth.traveler_default_role", {
                    defaultValue: "Inscription voyageur par défaut, sans compagnie.",
                  })}
                </p>
                <div className="space-y-2">
                  <Label htmlFor="signup-fullname">
                    {t("profile.full_name", { defaultValue: "Nom complet" })} *
                  </Label>
                  <Input
                    id="signup-fullname"
                    value={fullName}
                    onChange={(e) => setFullName(e.target.value)}
                    placeholder="Prénom Nom"
                    required
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="signup-phone">
                    {t("labels.phone", { defaultValue: "Téléphone" })} *
                  </Label>
                  <Input
                    id="signup-phone"
                    type="tel"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder="+225 07 00 00 00 00"
                    required
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="signup-email">Email</Label>
                  <Input
                    id="signup-email"
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="signup-password">Mot de passe</Label>
                  <Input
                    id="signup-password"
                    type="password"
                    minLength={6}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                  />
                </div>
                <CguAcceptanceCheckbox
                  id="signup-cgu"
                  checked={acceptedCgu}
                  onCheckedChange={setAcceptedCgu}
                />
                <Button type="submit" className="w-full" disabled={submitting || !acceptedCgu}>
                  {submitting ? <Spinner className="size-4" /> : t("auth.sign_up")}
                </Button>
                <div className="rounded-lg border bg-muted/40 p-3 text-sm">
                  <p className="font-medium">Vous voulez vendre des tickets ?</p>
                  <p className="text-muted-foreground text-xs mt-1">
                    Créez votre compte, puis envoyez votre demande Agent Marchand.
                  </p>
                  <Button asChild variant="secondary" className="mt-3 w-full gap-2">
                    <Link to={`/${lng ?? "fr"}/agent-marchand`}>
                      <StoreIcon className="w-4 h-4" />
                      Devenir Agent Marchand
                    </Link>
                  </Button>
                </div>
              </form>
            </TabsContent>
          </Tabs>

          <Button asChild variant="ghost" className="mt-4 w-full">
            <Link to={home}>{t("actions.back_home", { defaultValue: "Retour" })}</Link>
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}
