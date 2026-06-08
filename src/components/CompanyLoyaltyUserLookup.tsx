import { useEffect, useRef, useState } from "react";
import { SearchIcon, GiftIcon } from "lucide-react";
import { Input } from "@/components/ui/input.tsx";
import { useDebounce } from "@/hooks/use-debounce.ts";
import {
  lookupCompanyLoyaltyUsersSupabase,
  type CompanyLoyaltyLookupUser,
} from "@/lib/supabase/platform-loyalty.ts";

export type SelectedLoyaltyUser = {
  userId: string;
  displayName: string;
  phone: string | null;
  email: string | null;
  companyLoyaltyActive: boolean;
  companyPoints: number;
};

export default function CompanyLoyaltyUserLookup({
  companyId,
  query,
  onQueryChange,
  onSelect,
  disabled,
}: {
  companyId: string;
  query: string;
  onQueryChange: (value: string) => void;
  onSelect: (user: SelectedLoyaltyUser | null) => void;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [results, setResults] = useState<CompanyLoyaltyLookupUser[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [debounced] = useDebounce(query, 300);
  const wrapperRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (wrapperRef.current && !wrapperRef.current.contains(event.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  useEffect(() => {
    if (!companyId || debounced.trim().length < 2) {
      setResults(null);
      return;
    }
    let cancelled = false;
    setLoading(true);
    void lookupCompanyLoyaltyUsersSupabase(companyId, debounced.trim())
      .then((rows) => {
        if (!cancelled) setResults(rows);
      })
      .catch(() => {
        if (!cancelled) setResults([]);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [companyId, debounced]);

  const showDropdown = open && debounced.trim().length >= 2;

  return (
    <div ref={wrapperRef} className="relative">
      <div className="relative">
        <SearchIcon className="absolute left-2.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
        <Input
          value={query}
          disabled={disabled}
          onChange={(e) => {
            onQueryChange(e.target.value);
            onSelect(null);
            setOpen(true);
          }}
          onFocus={() => setOpen(true)}
          placeholder="Téléphone ou e-mail du compte voyageur"
          className="pl-9"
          autoComplete="off"
        />
      </div>

      {showDropdown ? (
        <div className="absolute z-50 top-full left-0 right-0 mt-1 bg-popover border rounded-lg shadow-lg max-h-56 overflow-y-auto">
          {loading || results === null ? (
            <p className="px-3 py-2 text-xs text-muted-foreground">Recherche…</p>
          ) : results.length === 0 ? (
            <p className="px-3 py-2 text-xs text-muted-foreground">
              Aucun compte Tibus trouvé — les points compagnie ne s&apos;appliqueront pas.
            </p>
          ) : (
            <div className="p-1">
              {results.map((user) => (
                <button
                  key={user.userId}
                  type="button"
                  className="w-full text-left px-2 py-2 rounded-md hover:bg-accent cursor-pointer"
                  onClick={() => {
                    onSelect({
                      userId: user.userId,
                      displayName: user.displayName,
                      phone: user.phone,
                      email: user.email,
                      companyLoyaltyActive: user.companyLoyaltyActive,
                      companyPoints: user.companyPoints,
                    });
                    onQueryChange(user.phone ?? user.email ?? user.displayName);
                    setOpen(false);
                  }}
                >
                  <div className="text-sm font-medium">{user.displayName}</div>
                  <div className="text-xs text-muted-foreground">
                    {user.phone ?? "—"}
                    {user.email ? ` · ${user.email}` : ""}
                    {user.companyLoyaltyActive ? (
                      <span className="inline-flex items-center gap-1 ml-2 text-primary">
                        <GiftIcon className="w-3 h-3" />
                        {user.companyPoints} pts
                      </span>
                    ) : null}
                  </div>
                </button>
              ))}
            </div>
          )}
        </div>
      ) : null}
    </div>
  );
}
