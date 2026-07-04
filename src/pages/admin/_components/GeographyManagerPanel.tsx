import { useCallback, useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  GlobeIcon,
  MapPinIcon,
  PencilIcon,
  PlusIcon,
  SearchIcon,
  Trash2Icon,
} from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Input } from "@/components/ui/input.tsx";
import { Label } from "@/components/ui/label.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog.tsx";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { recordPlatformAuditSupabase } from "@/lib/supabase/platform-audit-log.ts";
import {
  adminSearchCitiesSupabase,
  createCitySupabase,
  createCountrySupabase,
  deleteCitySupabase,
  deleteCountrySupabase,
  listCountriesSupabase,
  updateCitySupabase,
  updateCountrySupabase,
  type AdminCityRow,
  type CountryRow,
} from "@/lib/supabase/geography.ts";

const AUDIT_MODULE = "admin.geography";
const CITY_PAGE_SIZE = 100;
const ALL_COUNTRIES = "__all__";

type CountryDraft = { id: string | null; name: string; currency: string };
type CityDraft = { id: string | null; name: string; countryId: string };
type DeleteTarget =
  | { kind: "country"; id: string; name: string }
  | { kind: "city"; id: string; name: string };

type Props = {
  canManage: boolean;
  onDataChanged?: () => void;
};

// CRUD Pays & Villes (onglet géographie du panneau super admin).
// Les écritures sont protégées côté DB par RLS :
// is_super_admin() OR has_global_droit('manage_country').
export default function GeographyManagerPanel({ canManage, onDataChanged }: Props) {
  const { t } = useTranslation("admin");
  const { t: tc } = useTranslation("common");

  const [countries, setCountries] = useState<CountryRow[] | null>(null);
  const [countriesError, setCountriesError] = useState<string | null>(null);

  const [cityFilterCountryId, setCityFilterCountryId] = useState<string>(ALL_COUNTRIES);
  const [citySearch, setCitySearch] = useState("");
  const [debouncedCitySearch, setDebouncedCitySearch] = useState("");
  const [cityResult, setCityResult] = useState<{ rows: AdminCityRow[]; total: number } | null>(
    null,
  );
  const [citiesError, setCitiesError] = useState<string | null>(null);

  const [countryDraft, setCountryDraft] = useState<CountryDraft | null>(null);
  const [cityDraft, setCityDraft] = useState<CityDraft | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<DeleteTarget | null>(null);
  const [saving, setSaving] = useState(false);

  const loadCountries = useCallback(() => {
    setCountriesError(null);
    void listCountriesSupabase()
      .then(setCountries)
      .catch((err) => {
        setCountries([]);
        setCountriesError(err instanceof Error ? err.message : String(err));
      });
  }, []);

  const loadCities = useCallback(() => {
    setCitiesError(null);
    void adminSearchCitiesSupabase({
      countryId: cityFilterCountryId === ALL_COUNTRIES ? null : cityFilterCountryId,
      search: debouncedCitySearch,
      limit: CITY_PAGE_SIZE,
    })
      .then(setCityResult)
      .catch((err) => {
        setCityResult({ rows: [], total: 0 });
        setCitiesError(err instanceof Error ? err.message : String(err));
      });
  }, [cityFilterCountryId, debouncedCitySearch]);

  useEffect(() => {
    loadCountries();
  }, [loadCountries]);

  useEffect(() => {
    const handle = window.setTimeout(() => setDebouncedCitySearch(citySearch), 300);
    return () => window.clearTimeout(handle);
  }, [citySearch]);

  useEffect(() => {
    loadCities();
  }, [loadCities]);

  const countryNameById = useMemo(() => {
    const map = new Map<string, string>();
    for (const country of countries ?? []) map.set(country._id, country.name);
    return map;
  }, [countries]);

  const refreshAll = useCallback(() => {
    loadCountries();
    loadCities();
    onDataChanged?.();
  }, [loadCountries, loadCities, onDataChanged]);

  const friendlyError = (err: unknown, fallback: string) => {
    const message = err instanceof Error ? err.message : String(err);
    // 23503 : violation de clé étrangère (entité encore référencée).
    if (message.includes("23503") || message.toLowerCase().includes("foreign key")) {
      return t("geo.delete_in_use", {
        defaultValue:
          "Suppression impossible : cet élément est encore utilisé (villes, gares, utilisateurs ou compagnies).",
      });
    }
    return message || fallback;
  };

  // ── Pays ──────────────────────────────────────────────────────────────────
  const handleSaveCountry = async () => {
    if (!countryDraft || !countryDraft.name.trim()) return;
    setSaving(true);
    try {
      if (countryDraft.id) {
        await updateCountrySupabase(countryDraft.id, {
          name: countryDraft.name,
          currency: countryDraft.currency,
        });
        toast.success(t("geo.country_updated", { defaultValue: "Pays modifié." }));
        void recordPlatformAuditSupabase({
          moduleKey: AUDIT_MODULE,
          action: "update",
          summary: `Pays modifié : ${countryDraft.name.trim()}`,
          metadata: { countryId: countryDraft.id, currency: countryDraft.currency },
        });
      } else {
        await createCountrySupabase({
          name: countryDraft.name,
          currency: countryDraft.currency,
        });
        toast.success(t("geo.country_added"));
        void recordPlatformAuditSupabase({
          moduleKey: AUDIT_MODULE,
          action: "create",
          summary: `Pays ajouté : ${countryDraft.name.trim()}`,
          metadata: { currency: countryDraft.currency },
        });
      }
      setCountryDraft(null);
      refreshAll();
    } catch (err) {
      toast.error(friendlyError(err, t("geo.country_add_error")));
    } finally {
      setSaving(false);
    }
  };

  // ── Villes ────────────────────────────────────────────────────────────────
  const handleSaveCity = async () => {
    if (!cityDraft || !cityDraft.name.trim() || !cityDraft.countryId) return;
    setSaving(true);
    try {
      if (cityDraft.id) {
        await updateCitySupabase(cityDraft.id, {
          name: cityDraft.name,
          countryId: cityDraft.countryId,
        });
        toast.success(t("geo.city_updated", { defaultValue: "Ville modifiée." }));
        void recordPlatformAuditSupabase({
          moduleKey: AUDIT_MODULE,
          action: "update",
          summary: `Ville modifiée : ${cityDraft.name.trim()}`,
          metadata: { cityId: cityDraft.id, countryId: cityDraft.countryId },
        });
      } else {
        await createCitySupabase({
          name: cityDraft.name,
          countryId: cityDraft.countryId,
        });
        toast.success(t("geo.city_added"));
        void recordPlatformAuditSupabase({
          moduleKey: AUDIT_MODULE,
          action: "create",
          summary: `Ville ajoutée : ${cityDraft.name.trim()} (${countryNameById.get(cityDraft.countryId) ?? "?"})`,
          metadata: { countryId: cityDraft.countryId },
        });
      }
      setCityDraft(null);
      refreshAll();
    } catch (err) {
      toast.error(friendlyError(err, t("geo.city_add_error")));
    } finally {
      setSaving(false);
    }
  };

  // ── Suppression ───────────────────────────────────────────────────────────
  const handleConfirmDelete = async () => {
    if (!deleteTarget) return;
    setSaving(true);
    try {
      if (deleteTarget.kind === "country") {
        await deleteCountrySupabase(deleteTarget.id);
        toast.success(t("geo.country_deleted"));
      } else {
        await deleteCitySupabase(deleteTarget.id);
        toast.success(t("geo.city_deleted"));
      }
      void recordPlatformAuditSupabase({
        moduleKey: AUDIT_MODULE,
        action: "delete",
        summary:
          deleteTarget.kind === "country"
            ? `Pays supprimé : ${deleteTarget.name}`
            : `Ville supprimée : ${deleteTarget.name}`,
        metadata: { id: deleteTarget.id },
      });
      setDeleteTarget(null);
      refreshAll();
    } catch (err) {
      toast.error(friendlyError(err, t("geo.delete_error")));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="grid gap-4 md:grid-cols-2">
      {/* ── Pays ── */}
      <Card>
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between gap-2">
            <CardTitle className="text-base flex items-center gap-2">
              <GlobeIcon className="w-4 h-4" />
              {t("geo.countries")}
              {countries !== null ? (
                <Badge variant="secondary" className="text-[10px]">
                  {countries.length}
                </Badge>
              ) : null}
            </CardTitle>
            {canManage ? (
              <Button
                size="sm"
                className="cursor-pointer"
                onClick={() => setCountryDraft({ id: null, name: "", currency: "" })}
              >
                <PlusIcon className="w-4 h-4 mr-1" />
                {t("geo.add_country")}
              </Button>
            ) : null}
          </div>
        </CardHeader>
        <CardContent>
          {countries === null ? (
            <div className="space-y-2">
              {Array.from({ length: 4 }).map((_, i) => (
                <Skeleton key={i} className="h-11 w-full rounded-xl" />
              ))}
            </div>
          ) : countriesError ? (
            <p className="text-sm text-destructive">{countriesError}</p>
          ) : countries.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t("geo.no_countries")}</p>
          ) : (
            <div className="space-y-1 max-h-[480px] overflow-y-auto pr-1">
              {countries.map((country) => (
                <div
                  key={country._id}
                  className="flex items-center gap-3 p-2.5 rounded-xl hover:bg-muted/50"
                >
                  <GlobeIcon className="w-4 h-4 text-primary shrink-0" />
                  <div className="flex-1 min-w-0">
                    <div className="font-medium text-sm truncate">{country.name}</div>
                    <div className="text-xs text-muted-foreground">
                      {country.currency ?? "—"}
                    </div>
                  </div>
                  {canManage ? (
                    <div className="flex items-center gap-1 shrink-0">
                      <Button
                        variant="ghost"
                        size="sm"
                        className="cursor-pointer h-7 w-7 p-0"
                        aria-label={`${t("geo.edit_country", { defaultValue: "Modifier le pays" })} ${country.name}`}
                        onClick={() =>
                          setCountryDraft({
                            id: country._id,
                            name: country.name,
                            currency: country.currency ?? "",
                          })
                        }
                      >
                        <PencilIcon className="w-3.5 h-3.5" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="sm"
                        className="cursor-pointer h-7 w-7 p-0 text-destructive"
                        aria-label={`${tc("buttons.delete", { defaultValue: "Supprimer" })} ${country.name}`}
                        onClick={() =>
                          setDeleteTarget({
                            kind: "country",
                            id: country._id,
                            name: country.name,
                          })
                        }
                      >
                        <Trash2Icon className="w-3.5 h-3.5" />
                      </Button>
                    </div>
                  ) : null}
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* ── Villes ── */}
      <Card>
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between gap-2">
            <CardTitle className="text-base flex items-center gap-2">
              <MapPinIcon className="w-4 h-4" />
              {t("geo.cities", { defaultValue: "Villes" })}
              {cityResult !== null ? (
                <Badge variant="secondary" className="text-[10px]">
                  {cityResult.total}
                </Badge>
              ) : null}
            </CardTitle>
            {canManage ? (
              <Button
                size="sm"
                className="cursor-pointer"
                onClick={() =>
                  setCityDraft({
                    id: null,
                    name: "",
                    countryId:
                      cityFilterCountryId === ALL_COUNTRIES ? "" : cityFilterCountryId,
                  })
                }
              >
                <PlusIcon className="w-4 h-4 mr-1" />
                {t("geo.add_city")}
              </Button>
            ) : null}
          </div>
          <div className="flex flex-col sm:flex-row gap-2 pt-2">
            <div className="relative flex-1">
              <SearchIcon className="w-4 h-4 absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <Input
                value={citySearch}
                onChange={(e) => setCitySearch(e.target.value)}
                placeholder={t("geo.search_city", { defaultValue: "Rechercher une ville…" })}
                className="pl-8"
              />
            </div>
            <Select value={cityFilterCountryId} onValueChange={setCityFilterCountryId}>
              <SelectTrigger className="sm:w-44">
                <SelectValue placeholder={t("geo.select_country")} />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL_COUNTRIES}>
                  {t("geo.all_countries", { defaultValue: "Tous les pays" })}
                </SelectItem>
                {(countries ?? []).map((country) => (
                  <SelectItem key={country._id} value={country._id}>
                    {country.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </CardHeader>
        <CardContent>
          {cityResult === null ? (
            <div className="space-y-2">
              {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="h-10 w-full rounded-xl" />
              ))}
            </div>
          ) : citiesError ? (
            <p className="text-sm text-destructive">{citiesError}</p>
          ) : cityResult.rows.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              {t("geo.no_cities", { defaultValue: "Aucune ville." })}
            </p>
          ) : (
            <>
              <div className="space-y-1 max-h-[420px] overflow-y-auto pr-1">
                {cityResult.rows.map((city) => (
                  <div
                    key={city._id}
                    className="flex items-center gap-3 p-2 rounded-xl hover:bg-muted/50"
                  >
                    <MapPinIcon className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
                    <div className="flex-1 min-w-0">
                      <div className="text-sm truncate">{city.name}</div>
                      <div className="text-xs text-muted-foreground truncate">
                        {city.countryName ?? "—"}
                      </div>
                    </div>
                    {canManage ? (
                      <div className="flex items-center gap-1 shrink-0">
                        <Button
                          variant="ghost"
                          size="sm"
                          className="cursor-pointer h-7 w-7 p-0"
                          aria-label={`${t("geo.edit_city", { defaultValue: "Modifier la ville" })} ${city.name}`}
                          onClick={() =>
                            setCityDraft({
                              id: city._id,
                              name: city.name,
                              countryId: city.countryId,
                            })
                          }
                        >
                          <PencilIcon className="w-3.5 h-3.5" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          className="cursor-pointer h-7 w-7 p-0 text-destructive"
                          aria-label={`${tc("buttons.delete", { defaultValue: "Supprimer" })} ${city.name}`}
                          onClick={() =>
                            setDeleteTarget({ kind: "city", id: city._id, name: city.name })
                          }
                        >
                          <Trash2Icon className="w-3.5 h-3.5" />
                        </Button>
                      </div>
                    ) : null}
                  </div>
                ))}
              </div>
              {cityResult.total > cityResult.rows.length ? (
                <p className="text-xs text-muted-foreground mt-2">
                  {t("geo.showing_of_total", {
                    defaultValue:
                      "{{shown}} villes affichées sur {{total}} — affinez la recherche.",
                    shown: cityResult.rows.length,
                    total: cityResult.total,
                  })}
                </p>
              ) : null}
            </>
          )}
        </CardContent>
      </Card>

      {/* ── Dialog pays (créer / modifier) ── */}
      <Dialog
        open={countryDraft !== null}
        onOpenChange={(open) => {
          if (!open) setCountryDraft(null);
        }}
      >
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>
              {countryDraft?.id
                ? t("geo.edit_country", { defaultValue: "Modifier le pays" })
                : t("geo.add_country_title")}
            </DialogTitle>
            <DialogDescription>{t("geo.add_country_desc")}</DialogDescription>
          </DialogHeader>
          <div className="space-y-3 py-2">
            <div className="space-y-1.5">
              <Label>{t("geo.country_name")} *</Label>
              <Input
                value={countryDraft?.name ?? ""}
                onChange={(e) =>
                  setCountryDraft((draft) =>
                    draft ? { ...draft, name: e.target.value } : draft,
                  )
                }
                placeholder="ex. Cameroun"
              />
            </div>
            <div className="space-y-1.5">
              <Label>{t("geo.currency", { defaultValue: "Devise (ISO)" })}</Label>
              <Input
                value={countryDraft?.currency ?? ""}
                onChange={(e) =>
                  setCountryDraft((draft) =>
                    draft ? { ...draft, currency: e.target.value.toUpperCase() } : draft,
                  )
                }
                placeholder="ex. XAF"
                maxLength={8}
              />
            </div>
          </div>
          <DialogFooter>
            <Button
              variant="secondary"
              className="cursor-pointer"
              onClick={() => setCountryDraft(null)}
            >
              {tc("buttons.cancel")}
            </Button>
            <Button
              className="cursor-pointer"
              disabled={saving || !countryDraft?.name.trim()}
              onClick={() => void handleSaveCountry()}
            >
              {saving
                ? t("geo.adding")
                : countryDraft?.id
                  ? tc("buttons.save", { defaultValue: "Enregistrer" })
                  : t("geo.add_country")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ── Dialog ville (créer / modifier) ── */}
      <Dialog
        open={cityDraft !== null}
        onOpenChange={(open) => {
          if (!open) setCityDraft(null);
        }}
      >
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>
              {cityDraft?.id
                ? t("geo.edit_city", { defaultValue: "Modifier la ville" })
                : t("geo.add_city_title")}
            </DialogTitle>
            <DialogDescription>{t("geo.add_city_desc")}</DialogDescription>
          </DialogHeader>
          <div className="space-y-3 py-2">
            <div className="space-y-1.5">
              <Label>{t("geo.select_country")} *</Label>
              <Select
                value={cityDraft?.countryId ?? ""}
                onValueChange={(value) =>
                  setCityDraft((draft) =>
                    draft ? { ...draft, countryId: value } : draft,
                  )
                }
              >
                <SelectTrigger>
                  <SelectValue placeholder={t("geo.select_country")} />
                </SelectTrigger>
                <SelectContent>
                  {(countries ?? []).map((country) => (
                    <SelectItem key={country._id} value={country._id}>
                      {country.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>{t("geo.city_name")} *</Label>
              <Input
                value={cityDraft?.name ?? ""}
                onChange={(e) =>
                  setCityDraft((draft) =>
                    draft ? { ...draft, name: e.target.value } : draft,
                  )
                }
                placeholder="ex. Douala"
              />
            </div>
          </div>
          <DialogFooter>
            <Button
              variant="secondary"
              className="cursor-pointer"
              onClick={() => setCityDraft(null)}
            >
              {tc("buttons.cancel")}
            </Button>
            <Button
              className="cursor-pointer"
              disabled={saving || !cityDraft?.name.trim() || !cityDraft?.countryId}
              onClick={() => void handleSaveCity()}
            >
              {saving
                ? t("geo.adding")
                : cityDraft?.id
                  ? tc("buttons.save", { defaultValue: "Enregistrer" })
                  : t("geo.add_city")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ── Confirmation de suppression ── */}
      <AlertDialog
        open={deleteTarget !== null}
        onOpenChange={(open) => {
          if (!open) setDeleteTarget(null);
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {deleteTarget?.kind === "country"
                ? t("geo.delete_country_title", { defaultValue: "Supprimer ce pays ?" })
                : t("geo.delete_city_title", { defaultValue: "Supprimer cette ville ?" })}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {deleteTarget?.kind === "country"
                ? t("geo.delete_country_desc", {
                    defaultValue:
                      "« {{name}} » sera supprimé définitivement. Impossible si des villes, utilisateurs ou compagnies y sont rattachés.",
                    name: deleteTarget?.name ?? "",
                  })
                : t("geo.delete_city_desc", {
                    defaultValue:
                      "« {{name}} » sera supprimée définitivement. Impossible si des gares ou trajets y sont rattachés.",
                    name: deleteTarget?.name ?? "",
                  })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel className="cursor-pointer">
              {tc("buttons.cancel")}
            </AlertDialogCancel>
            <AlertDialogAction
              className="cursor-pointer bg-destructive text-destructive-foreground hover:bg-destructive/90"
              disabled={saving}
              onClick={(e) => {
                e.preventDefault();
                void handleConfirmDelete();
              }}
            >
              {tc("buttons.delete", { defaultValue: "Supprimer" })}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
