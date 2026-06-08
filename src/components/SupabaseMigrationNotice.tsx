import { Link, useParams } from "react-router-dom";
import { Button } from "@/components/ui/button.tsx";

type Props = {
  title: string;
  description?: string;
};

export function SupabaseMigrationNotice({ title, description }: Props) {
  const { lng } = useParams<{ lng: string }>();

  return (
    <div className="p-6 max-w-lg mx-auto text-center space-y-4">
      <h2 className="text-lg font-bold">{title}</h2>
      <p className="text-sm text-muted-foreground">
        {description ??
          "Ce module Convex n'est pas encore branché sur Supabase en production."}
      </p>
      <Button asChild variant="secondary">
        <Link to={`/${lng ?? "fr"}/owner`}>Retour au tableau de bord</Link>
      </Button>
    </div>
  );
}
