import { useCallback, useEffect, useMemo, useState } from "react";
import { GlobeIcon, PlusIcon, XIcon } from "lucide-react";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select.tsx";
import { useAppUser } from "@/hooks/use-app-user";
import {
  adminGrantCompanyOperatingCountrySupabase,
  adminRevokeCompanyOperatingCountrySupabase,
  listCompanyAvailableCountriesSupabase,
  listCountriesSupabase,
  type CountryRow,
} from "@/lib/supabase/geography.ts";

type Props = {
  companyId: string;
  homeCountryId: string | null;
  homeCountryName: string | null;
};

// Panneau super admin : pays d'opération autorisés pour les gares /
// itinéraires transfrontaliers (table CompanyOperatingCountries).
export default function CompanyOperatingCountriesPanel({
  companyId,
  homeCountryId,
  homeCountryName,
}: Props) {
  const { isSuperAdmin } = useAppUser();
  const [granted, setGranted] = useState<CountryRow[] | null>(null);
  const [allCountries, setAllCountries] = useState<CountryRow[]>([]);
  const [draftCountryId, setDraftCountryId] = useState<string>("");
  const [saving, setSaving] = useState(false);

  const load = useCallback(() => {
    void listCompanyAvailableCountriesSupabase(companyId)
      .then((countries) =>
        setGranted(countries.filter((c) => c._id !== homeCountryId)),
      )
      .catch((err) => {
        toast.error(
          err instanceof Error ? err.message : "Chargement des pays impossible.",
        );
        setGranted([]);
      });
  }, [companyId, homeCountryId]);

  useEffect(() => {
    if (!isSuperAdmin) return;
    load();
    void listCountriesSupabase()
      .then(setAllCountries)
      .catch(() => setAllCountries([]));
  }, [isSuperAdmin, load]);

  const grantableCountries = useMemo(() => {
    const grantedIds = new Set((granted ?? []).map((c) => c._id));
    return allCountries.filter(
      (c) => c._id !== homeCountryId && !grantedIds.has(c._id),
    );
  }, [allCountries, granted, homeCountryId]);

  if (!isSuperAdmin) return null;

  const handleGrant = async () => {
    if (!draftCountryId) return;
    setSaving(true);
    try {
      await adminGrantCompanyOperatingCountrySupabase(companyId, draftCountryId);
      toast.success("Pays d'opération autorisé.");
      setDraftCountryId("");
      load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Autorisation impossible.");
    } finally {
      setSaving(false);
    }
  };

  const handleRevoke = async (countryId: string) => {
    setSaving(true);
    try {
      await adminRevokeCompanyOperatingCountrySupabase(companyId, countryId);
      toast.success("Autorisation révoquée.");
      load();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Révocation impossible.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base flex items-center gap-2">
          <GlobeIcon className="w-4 h-4" />
          Pays d'opération (transfrontalier)
        </CardTitle>
        <p className="text-xs text-muted-foreground">
          Pays dans lesquels la compagnie est autorisée à créer des gares, en plus de
          son pays d'origine. Requis pour les itinéraires transfrontaliers.
        </p>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap gap-2">
          {homeCountryName ? (
            <Badge variant="default">{homeCountryName} (origine)</Badge>
          ) : null}
          {granted === null ? (
            <Skeleton className="h-6 w-32" />
          ) : (
            granted.map((country) => (
              <Badge key={country._id} variant="outline" className="gap-1 pr-1">
                {country.name}
                <button
                  type="button"
                  aria-label={`Révoquer ${country.name}`}
                  disabled={saving}
                  className="rounded-full hover:bg-muted p-0.5 disabled:opacity-50"
                  onClick={() => void handleRevoke(country._id)}
                >
                  <XIcon className="w-3 h-3" />
                </button>
              </Badge>
            ))
          )}
          {granted !== null && granted.length === 0 ? (
            <span className="text-xs text-muted-foreground">
              Aucun pays supplémentaire autorisé.
            </span>
          ) : null}
        </div>

        <div className="flex items-end gap-2 max-w-md">
          <div className="flex-1 space-y-1.5">
            <Select value={draftCountryId} onValueChange={setDraftCountryId}>
              <SelectTrigger>
                <SelectValue placeholder="Ajouter un pays…" />
              </SelectTrigger>
              <SelectContent>
                {grantableCountries.map((country) => (
                  <SelectItem key={country._id} value={country._id}>
                    {country.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <Button
            size="sm"
            disabled={saving || !draftCountryId}
            onClick={() => void handleGrant()}
          >
            <PlusIcon className="w-4 h-4 mr-1" />
            Autoriser
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
