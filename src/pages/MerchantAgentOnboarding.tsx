import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { toast } from "sonner";
import {
  ArrowLeftIcon,
  CheckCircleIcon,
  MapPinIcon,
  StoreIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Textarea } from "@/components/ui/textarea.tsx";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import { useAppUser } from "@/hooks/use-app-user.ts";
import { useSupabaseAuth } from "@/components/providers/supabase-auth";
import {
  getMyMerchantAgentApplication,
  listMerchantAgentCities,
  listMerchantAgentCountries,
  submitMerchantAgentApplication,
  type MerchantAgentCity,
  type MerchantAgentCountry,
} from "@/lib/supabase/merchant-agent";

function isLikelyMapUrl(value: string) {
  const normalized = value.trim().toLowerCase();
  return (
    normalized.startsWith("https://") &&
    (normalized.includes("maps.google") ||
      normalized.includes("google.com/maps") ||
      normalized.includes("goo.gl/maps") ||
      normalized.includes("maps.app.goo.gl"))
  );
}

export default function MerchantAgentOnboarding() {
  const { lng } = useParams<{ lng: string }>();
  const navigate = useNavigate();
  const { appUserId, session, signUpWithPassword } = useSupabaseAuth();
  const appUser = useAppUser();
  const [countries, setCountries] = useState<MerchantAgentCountry[]>([]);
  const [cities, setCities] = useState<MerchantAgentCity[]>([]);
  const [existing, setExisting] = useState<{
    id: string;
    status: string;
    commercialName: string;
    createdAt: string;
  } | null>(null);
  const [checkingExisting, setCheckingExisting] = useState(false);
  const [loadingCities, setLoadingCities] = useState(false);
  const [loading, setLoading] = useState(false);
  const [isConfirming, setIsConfirming] = useState(false);
  const [form, setForm] = useState({
    commercialName: "",
    fullName: "",
    phone: "",
    email: "",
    countryId: "",
    countryName: "",
    cityId: "",
    city: "",
    physicalAddress: "",
    googleMapsUrl: "",
  });
  const [password, setPassword] = useState("");

  useEffect(() => {
    let cancelled = false;
    void listMerchantAgentCountries()
      .then((rows) => {
        if (!cancelled) setCountries(rows);
      })
      .catch(() => {
        if (!cancelled) setCountries([]);
      });

    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!appUserId) {
      setExisting(null);
      setCheckingExisting(false);
      return;
    }

    let cancelled = false;
    setCheckingExisting(true);
    void getMyMerchantAgentApplication(appUserId)
      .then((row) => {
        if (!cancelled) setExisting(row as typeof existing);
      })
      .catch(() => {
        if (!cancelled) setExisting(null);
      })
      .finally(() => {
        if (!cancelled) setCheckingExisting(false);
      });

    return () => {
      cancelled = true;
    };
  }, [appUserId]);

  useEffect(() => {
    if (!appUser.profile) return;
    setForm((current) => ({
      ...current,
      fullName:
        current.fullName ||
        `${appUser.profile?.firstName ?? ""} ${appUser.profile?.lastName ?? ""}`.trim(),
      phone: current.phone || appUser.profile?.phone || "",
      email: current.email || appUser.profile?.email || "",
      countryId: current.countryId || appUser.profile?.countryId || "",
    }));
  }, [appUser.profile]);

  useEffect(() => {
    if (!form.countryId) {
      setCities([]);
      setLoadingCities(false);
      return;
    }

    let cancelled = false;
    setLoadingCities(true);
    void listMerchantAgentCities(form.countryId)
      .then((rows) => {
        if (!cancelled) setCities(rows);
      })
      .catch(() => {
        if (!cancelled) setCities([]);
      })
      .finally(() => {
        if (!cancelled) setLoadingCities(false);
      });

    return () => {
      cancelled = true;
    };
  }, [form.countryId]);

  const selectedCountryName = useMemo(() => {
    return countries.find((country) => country.id === form.countryId)?.name ?? form.countryName;
  }, [countries, form.countryId, form.countryName]);

  const selectedCityName = useMemo(() => {
    return cities.find((city) => city.id === form.cityId)?.name ?? form.city;
  }, [cities, form.city, form.cityId]);

  const needsAccount = !appUserId && !session;

  const setField = (field: keyof typeof form, value: string) => {
    setIsConfirming(false);
    setForm((current) => ({ ...current, [field]: value }));
  };

  const handleCountryChange = (countryId: string) => {
    setIsConfirming(false);
    setForm((current) => ({
      ...current,
      countryId,
      countryName: "",
      cityId: "",
      city: "",
    }));
  };

  const handleCityChange = (cityId: string) => {
    const city = cities.find((option) => option.id === cityId);
    setIsConfirming(false);
    setForm((current) => ({
      ...current,
      cityId,
      city: city?.name ?? "",
    }));
  };

  const validateForm = () => {
    if (!form.commercialName.trim()) {
      toast.error("Nom commercial requis");
      return null;
    }
    if (!form.fullName.trim()) {
      toast.error("Nom complet requis");
      return null;
    }
    if (!form.phone.trim()) {
      toast.error("Téléphone requis");
      return null;
    }
    if (!form.countryId || !selectedCountryName.trim()) {
      toast.error("Pays requis");
      return null;
    }
    if (loadingCities) {
      toast.info("Chargement des villes en cours");
      return null;
    }
    if (!form.cityId || !selectedCityName.trim()) {
      toast.error("Ville requise");
      return null;
    }
    if (!form.physicalAddress.trim()) {
      toast.error("Adresse physique requise");
      return null;
    }
    if (!isLikelyMapUrl(form.googleMapsUrl)) {
      toast.error("Collez un lien Google Maps valide");
      return null;
    }

    const normalizedEmail = form.email.trim();

    if (needsAccount && !normalizedEmail) {
      toast.error("Email requis pour créer votre compte");
      return null;
    }
    if (needsAccount && password.trim().length < 6) {
      toast.error("Mot de passe requis (6 caractères minimum)");
      return null;
    }
    if (!appUserId && session) {
      toast.info("Votre profil est en cours de préparation. Réessayez dans un instant.");
      return null;
    }

    return normalizedEmail;
  };

  const handleReview = () => {
    if (validateForm() === null) return;
    setIsConfirming(true);
  };

  const handleSubmit = async () => {
    const normalizedEmail = validateForm();
    if (normalizedEmail === null) return;

    setLoading(true);
    try {
      let submissionAppUserId = appUserId;

      if (!submissionAppUserId) {
        const signUpResult = await signUpWithPassword(normalizedEmail, password);
        submissionAppUserId = signUpResult.appUserId;

        if (!submissionAppUserId) {
          toast.info(
            signUpResult.requiresConfirmation
              ? "Compte créé. Confirmez votre email puis connectez-vous pour finaliser votre demande Agent Marchand."
              : "Compte créé. Connectez-vous pour finaliser votre demande Agent Marchand.",
          );
          navigate(`/${lng ?? "fr"}/auth/login`, { replace: true });
          return;
        }
      }

      await submitMerchantAgentApplication({
        commercialName: form.commercialName,
        fullName: form.fullName,
        phone: form.phone,
        email: normalizedEmail,
        countryId: form.countryId,
        countryName: selectedCountryName,
        cityId: form.cityId,
        city: selectedCityName,
        physicalAddress: form.physicalAddress,
        googleMapsUrl: form.googleMapsUrl,
      });
      toast.success("Demande Agent Marchand envoyée");
      navigate(`/${lng ?? "fr"}`, { replace: true });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Envoi impossible");
    } finally {
      setLoading(false);
    }
  };

  if (appUser.isLoading || checkingExisting) {
    return (
      <div className="max-w-2xl mx-auto px-4 py-8 space-y-4">
        <Skeleton className="h-8 w-48" />
        <Skeleton className="h-96 w-full rounded-xl" />
      </div>
    );
  }

  if (existing) {
    return (
      <div className="max-w-md mx-auto px-4 py-10">
        <Card className="border-2 border-primary/20">
          <CardHeader className="text-center">
            <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-3">
              <CheckCircleIcon className="w-7 h-7 text-primary" />
            </div>
            <CardTitle>Demande déjà envoyée</CardTitle>
            <CardDescription>
              Votre demande “{existing.commercialName}” est actuellement : {existing.status}.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Button asChild className="w-full">
              <Link to={`/${lng ?? "fr"}`}>Retour à l'accueil</Link>
            </Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-5">
      <Link
        to={`/${lng ?? "fr"}`}
        className="inline-flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground"
      >
        <ArrowLeftIcon className="w-4 h-4" /> Retour
      </Link>

      <Card className="border-2 border-primary/15">
        <CardHeader className="space-y-2">
          <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center">
            <StoreIcon className="w-7 h-7 text-primary" />
          </div>
          <div>
            <CardTitle>Devenir Agent Marchand</CardTitle>
            <CardDescription>
              Remplissez ce formulaire pour demander votre enrôlement comme point de vente Tibus.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent className="space-y-5">
          {!appUserId && !session && (
            <div className="rounded-lg border bg-muted/40 p-3 text-sm text-muted-foreground">
              Créez votre compte pendant l'envoi de la demande. Si la confirmation email est
              activée, vous devrez confirmer votre adresse avant la finalisation.
            </div>
          )}
          {isConfirming ? (
            <div className="space-y-4">
              <div className="rounded-lg border bg-muted/30 p-4 space-y-3">
                <p className="font-semibold">Confirmez vos informations</p>
                <div className="grid gap-3 text-sm sm:grid-cols-2">
                  <div>
                    <p className="text-xs text-muted-foreground">Nom commercial</p>
                    <p className="font-medium">{form.commercialName.trim()}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Nom complet</p>
                    <p className="font-medium">{form.fullName.trim()}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Téléphone</p>
                    <p className="font-medium">{form.phone.trim()}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Email</p>
                    <p className="font-medium">{form.email.trim() || "Non renseigné"}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Pays</p>
                    <p className="font-medium">{selectedCountryName}</p>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Ville</p>
                    <p className="font-medium">{selectedCityName}</p>
                  </div>
                  <div className="sm:col-span-2">
                    <p className="text-xs text-muted-foreground">Adresse physique</p>
                    <p className="font-medium">{form.physicalAddress.trim()}</p>
                  </div>
                  <div className="sm:col-span-2">
                    <p className="text-xs text-muted-foreground">Lien Google Maps</p>
                    <p className="font-medium break-all">{form.googleMapsUrl.trim()}</p>
                  </div>
                </div>
              </div>
              <div className="flex flex-col-reverse gap-2 sm:flex-row">
                <Button
                  variant="outline"
                  className="flex-1"
                  onClick={() => setIsConfirming(false)}
                  disabled={loading}
                >
                  Modifier
                </Button>
                <Button className="flex-1" size="lg" onClick={handleSubmit} disabled={loading}>
                  {loading ? "Finalisation..." : "Confirmer et finaliser"}
                </Button>
              </div>
            </div>
          ) : (
            <>
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-1.5 sm:col-span-2">
                  <Label>Nom commercial *</Label>
                  <Input
                    value={form.commercialName}
                    onChange={(event) => setField("commercialName", event.target.value)}
                    placeholder="Ex: Kiosk Tibus Agoè"
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>Nom complet *</Label>
                  <Input
                    value={form.fullName}
                    onChange={(event) => setField("fullName", event.target.value)}
                    placeholder="Nom et prénom"
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>Téléphone *</Label>
                  <Input
                    value={form.phone}
                    onChange={(event) => setField("phone", event.target.value)}
                    placeholder="+228..."
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>Email {needsAccount ? "*" : ""}</Label>
                  <Input
                    type="email"
                    value={form.email}
                    onChange={(event) => setField("email", event.target.value)}
                    placeholder="agent@example.com"
                  />
                </div>
                {needsAccount && (
                  <div className="space-y-1.5">
                    <Label>Mot de passe *</Label>
                    <Input
                      type="password"
                      minLength={6}
                      value={password}
                      onChange={(event) => {
                        setIsConfirming(false);
                        setPassword(event.target.value);
                      }}
                      placeholder="6 caractères minimum"
                    />
                  </div>
                )}
                <div className="space-y-1.5">
                  <Label>Pays *</Label>
                  <Select value={form.countryId} onValueChange={handleCountryChange}>
                    <SelectTrigger>
                      <SelectValue placeholder="Sélectionner un pays" />
                    </SelectTrigger>
                    <SelectContent>
                      {countries.map((country) => (
                        <SelectItem key={country.id} value={country.id}>
                          {country.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {countries.length === 0 && (
                    <p className="text-xs text-muted-foreground">
                      Aucun pays disponible pour le moment.
                    </p>
                  )}
                </div>
                <div className="space-y-1.5">
                  <Label>Ville *</Label>
                  <Select
                    value={form.cityId}
                    onValueChange={handleCityChange}
                    disabled={!form.countryId || loadingCities || cities.length === 0}
                  >
                    <SelectTrigger>
                      <SelectValue
                        placeholder={
                          !form.countryId
                            ? "Sélectionnez d'abord un pays"
                            : loadingCities
                              ? "Chargement des villes..."
                              : "Sélectionner une ville"
                        }
                      />
                    </SelectTrigger>
                    <SelectContent>
                      {cities.map((city) => (
                        <SelectItem key={city.id} value={city.id}>
                          {city.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {form.countryId && !loadingCities && cities.length === 0 && (
                    <p className="text-xs text-muted-foreground">
                      Aucune ville configurée pour ce pays.
                    </p>
                  )}
                </div>
                <div className="space-y-1.5 sm:col-span-2">
                  <Label>Adresse physique *</Label>
                  <Textarea
                    value={form.physicalAddress}
                    onChange={(event) => setField("physicalAddress", event.target.value)}
                    placeholder="Quartier, rue, repère..."
                  />
                </div>
                <div className="space-y-1.5 sm:col-span-2">
                  <Label>Lien géolocalisation Google Maps *</Label>
                  <Input
                    value={form.googleMapsUrl}
                    onChange={(event) => setField("googleMapsUrl", event.target.value)}
                    placeholder="https://maps.app.goo.gl/..."
                  />
                  <div className="rounded-lg border bg-muted/40 p-3 text-xs text-muted-foreground space-y-1">
                    <p className="font-semibold text-foreground flex items-center gap-1.5">
                      <MapPinIcon className="w-3.5 h-3.5" /> Comment obtenir le lien ?
                    </p>
                    <p>
                      Ouvrez Google Maps, cherchez votre emplacement, cliquez sur “Partager”,
                      puis copiez-collez le lien ici.
                    </p>
                  </div>
                </div>
              </div>

              <Button className="w-full" size="lg" onClick={handleReview} disabled={loading}>
                Continuer vers la confirmation
              </Button>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
