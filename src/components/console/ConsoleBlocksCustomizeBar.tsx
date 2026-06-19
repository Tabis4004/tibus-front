import { useTranslation } from "react-i18next";
import { PaletteIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import { cn } from "@/lib/utils.ts";

type Props = {
  active: boolean;
  onToggle: () => void;
  className?: string;
};

export default function ConsoleBlocksCustomizeBar({ active, onToggle, className }: Props) {
  const { t } = useTranslation("common");

  return (
    <div className={cn("flex justify-end", className)}>
      <Button
        type="button"
        variant={active ? "default" : "outline"}
        size="sm"
        className="gap-2"
        onClick={onToggle}
      >
        <PaletteIcon className="w-4 h-4" />
        {t("console_blocks.customize_colors", { defaultValue: "Personnaliser les couleurs" })}
      </Button>
    </div>
  );
}
