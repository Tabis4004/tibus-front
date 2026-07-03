import { useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  AlertTriangleIcon,
  CheckIcon,
  ChevronsUpDownIcon,
  Loader2Icon,
  PlusIcon,
} from "lucide-react";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button.tsx";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover.tsx";
import {
  Command,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command.tsx";
import {
  findOrCreateCitySupabase,
  normalizeCityName,
  verifyCityExistsExternally,
} from "@/lib/supabase/geography.ts";

type City = { id: string; name: string };

// Autocomplete ville (insensible casse/accents) pour le formulaire gare.
// Si la ville n'existe pas encore : vérification externe (OpenStreetMap)
// puis création via find_or_create_city — la ville devient disponible pour
// toutes les compagnies opérant dans ce pays.
export default function CityCombobox({
  cities,
  value,
  onChange,
  companyId,
  countryId,
  countryName,
  onCityCreated,
  disabled,
}: {
  cities: City[];
  value: string;
  onChange: (cityId: string) => void;
  companyId: string;
  countryId: string | null;
  countryName: string | null;
  onCityCreated: (city: City) => void;
  disabled?: boolean;
}) {
  const { t } = useTranslation("owner");
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const [busy, setBusy] = useState(false);
  // Nom saisi non confirmé par OpenStreetMap, en attente de confirmation
  // « Créer quand même » par l'utilisateur.
  const [unverifiedName, setUnverifiedName] = useState<string | null>(null);

  const selected = cities.find((city) => city.id === value) ?? null;
  const normSearch = normalizeCityName(search);

  const filtered = useMemo(() => {
    const list = normSearch
      ? cities.filter((city) => normalizeCityName(city.name).includes(normSearch))
      : cities;
    return list.slice(0, 100);
  }, [cities, normSearch]);

  const exactMatch = useMemo(
    () =>
      normSearch
        ? cities.find((city) => normalizeCityName(city.name) === normSearch) ?? null
        : null,
    [cities, normSearch],
  );

  const handleSearchChange = (next: string) => {
    setSearch(next);
    setUnverifiedName(null);
  };

  const selectCity = (cityId: string) => {
    onChange(cityId);
    setOpen(false);
    setSearch("");
    setUnverifiedName(null);
  };

  const createCity = async (name: string) => {
    if (!countryId) return;
    setBusy(true);
    try {
      const row = await findOrCreateCitySupabase(companyId, countryId, name);
      if (row.created) {
        toast.success(t("stations.city_created", { name: row.name }));
      }
      onCityCreated({ id: row.id, name: row.name });
      selectCity(row.id);
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : t("stations.city_create_error"),
      );
    } finally {
      setBusy(false);
    }
  };

  const handleCreateRequest = async () => {
    const name = search.trim();
    if (!name || !countryId) return;
    if (exactMatch) {
      selectCity(exactMatch.id);
      return;
    }
    setBusy(true);
    try {
      const verified = await verifyCityExistsExternally(name, countryName);
      if (verified) {
        await createCity(name);
      } else {
        // Non trouvée dans OpenStreetMap : avertir sans bloquer.
        setUnverifiedName(name);
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          type="button"
          variant="outline"
          role="combobox"
          aria-expanded={open}
          disabled={disabled || !countryId}
          className="w-full justify-between font-normal"
        >
          <span className={cn(!selected && "text-muted-foreground")}>
            {selected ? selected.name : t("stations.city_placeholder")}
          </span>
          <ChevronsUpDownIcon className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[var(--radix-popover-trigger-width)] p-0" align="start">
        <Command shouldFilter={false}>
          <CommandInput
            placeholder={t("stations.city_search_placeholder")}
            value={search}
            onValueChange={handleSearchChange}
          />
          <CommandList>
            <CommandGroup>
              {filtered.map((city) => (
                <CommandItem
                  key={city.id}
                  value={city.id}
                  onSelect={() => selectCity(city.id)}
                >
                  <CheckIcon
                    className={cn(
                      "mr-2 h-4 w-4",
                      city.id === value ? "opacity-100" : "opacity-0",
                    )}
                  />
                  {city.name}
                </CommandItem>
              ))}
              {filtered.length === 0 && !search.trim() ? (
                <div className="py-3 text-center text-sm text-muted-foreground">
                  {t("stations.city_no_match")}
                </div>
              ) : null}
              {search.trim().length >= 2 && !exactMatch ? (
                <CommandItem
                  value={`__create__${search}`}
                  disabled={busy}
                  onSelect={() => void handleCreateRequest()}
                  className="text-primary"
                >
                  {busy ? (
                    <Loader2Icon className="mr-2 h-4 w-4 animate-spin" />
                  ) : (
                    <PlusIcon className="mr-2 h-4 w-4" />
                  )}
                  {busy
                    ? t("stations.city_verifying")
                    : t("stations.city_create", { name: search.trim() })}
                </CommandItem>
              ) : null}
            </CommandGroup>
          </CommandList>
          {unverifiedName ? (
            <div className="border-t p-3 space-y-2">
              <p className="text-xs text-muted-foreground flex items-start gap-1.5">
                <AlertTriangleIcon className="w-3.5 h-3.5 shrink-0 mt-0.5 text-amber-500" />
                {t("stations.city_not_verified", {
                  name: unverifiedName,
                  country: countryName ?? "—",
                })}
              </p>
              <Button
                type="button"
                size="sm"
                variant="outline"
                className="w-full"
                disabled={busy}
                onClick={() => void createCity(unverifiedName)}
              >
                {busy ? (
                  <Loader2Icon className="mr-2 h-4 w-4 animate-spin" />
                ) : (
                  <PlusIcon className="mr-2 h-4 w-4" />
                )}
                {t("stations.city_create_anyway")}
              </Button>
            </div>
          ) : null}
        </Command>
      </PopoverContent>
    </Popover>
  );
}
