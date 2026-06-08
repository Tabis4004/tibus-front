import { useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "@/lib/supabase";
import { Spinner } from "@/components/ui/spinner.tsx";
import { SAVED_OR_DEFAULT_LOCALE } from "@/i18n";

export default function SupabaseCallback() {
  const navigate = useNavigate();

  useEffect(() => {
    supabase.auth.getSession().then(() => {
      navigate(`/${SAVED_OR_DEFAULT_LOCALE}`, { replace: true });
    });
  }, [navigate]);

  return (
    <div className="flex h-svh flex-col items-center justify-center gap-4">
      <Spinner className="size-8" />
      <p className="text-sm text-muted-foreground">Connexion en cours…</p>
    </div>
  );
}
