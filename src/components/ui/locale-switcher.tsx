import { Button } from "@/components/ui/button.tsx";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu.tsx";
import {
  setLocaleInPath,
  SUPPORTED_LOCALES,
  SUPPORTED_LOCALES_ARRAY,
  type SupportedLocale,
} from "@/i18n";
import { cn } from "@/lib/utils.ts";
import { Check, Globe } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useLocation, useNavigate } from "react-router-dom";

export default function LocaleSwitcher() {
  const { i18n } = useTranslation();
  const navigate = useNavigate();
  const location = useLocation();
  const currentMeta = SUPPORTED_LOCALES[i18n.language as keyof typeof SUPPORTED_LOCALES];

  const handleChangeLocale = (newLng: SupportedLocale) => {
    const newPath = setLocaleInPath(newLng, location.pathname, location.search, location.hash);
    navigate(newPath);
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="sm" className="cursor-pointer gap-1.5 px-2">
          <Globe className="h-4 w-4" />
          <span className="text-xs">{currentMeta?.emoji}</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {SUPPORTED_LOCALES_ARRAY.map((lng) => {
          const meta = SUPPORTED_LOCALES[lng];
          const isActive = i18n.language === lng;
          return (
            <DropdownMenuItem
              key={lng}
              onClick={() => handleChangeLocale(lng)}
              className="cursor-pointer"
            >
              <Check className={cn("mr-2 h-4 w-4", isActive ? "opacity-100" : "opacity-0")} />
              <span className="mr-2">{meta.emoji}</span>
              <span className="flex-1">{meta.nativeName}</span>
            </DropdownMenuItem>
          );
        })}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
