import { useEffect } from "react";
import { Link, useLocation, useParams } from "react-router-dom";
import { Button } from "@/components/ui/button.tsx";
import { useTranslation } from "react-i18next";

export default function NotFound() {
  const location = useLocation();
  const { t } = useTranslation("common");
  const { lng } = useParams<{ lng: string }>();

  useEffect(() => {
    console.error(
      "404 Error: User attempted to access non-existent route:",
      location.pathname,
    );
  }, [location.pathname]);

  return (
    <div className="min-h-screen flex items-center justify-center bg-background">
      <div className="text-center space-y-6">
        <div className="space-y-2">
          <h1 className="text-6xl font-bold text-muted-foreground">404</h1>
          <h2 className="text-2xl font-semibold">{t("notfound.title")}</h2>
        </div>
        <p className="text-lg text-muted-foreground max-w-md mx-auto">
          {t("notfound.description")}
        </p>
        <div className="pt-4">
          <Button asChild>
            <Link to={`/${lng}`}>{t("notfound.back")}</Link>
          </Button>
        </div>
      </div>
    </div>
  );
}
