import { useTranslation } from "react-i18next";
import { CONSOLE_TILE_PALETTES } from "@/lib/console-grid-tiles.ts";
import { cn } from "@/lib/utils.ts";

type Props = {
  blockId: string;
  selectedIndex: number;
  defaultIndex: number;
  onSelect: (index: number) => void;
  onReset: () => void;
};

export default function ConsoleTilePalettePicker({
  selectedIndex,
  defaultIndex,
  onSelect,
  onReset,
}: Props) {
  const { t } = useTranslation("common");
  const isCustom = selectedIndex !== defaultIndex;

  return (
    <div
      className="mt-2 pt-2 border-t border-black/5 dark:border-white/10 w-full"
      onClick={(e) => e.preventDefault()}
    >
      <p className="text-[9px] uppercase tracking-wide text-muted-foreground mb-1.5">
        {t("console_blocks.pastel_color", { defaultValue: "Couleur pastel" })}
      </p>
      <div className="flex flex-wrap items-center justify-center gap-1">
        {CONSOLE_TILE_PALETTES.map((palette, index) => (
          <button
            key={index}
            type="button"
            title={t("console_blocks.color_n", { defaultValue: "Couleur {{n}}", n: index + 1 })}
            onClick={(e) => {
              e.preventDefault();
              e.stopPropagation();
              onSelect(index);
            }}
            className={cn(
              "w-5 h-5 rounded-full border-2 transition-transform hover:scale-110",
              palette.iconWrap,
              selectedIndex === index
                ? "border-foreground ring-1 ring-foreground/30 scale-110"
                : "border-transparent opacity-80",
            )}
          />
        ))}
        <button
          type="button"
          onClick={(e) => {
            e.preventDefault();
            e.stopPropagation();
            onReset();
          }}
          disabled={!isCustom}
          className={cn(
            "ml-1 px-1.5 py-0.5 rounded text-[9px] font-medium",
            isCustom
              ? "text-muted-foreground hover:text-foreground hover:bg-muted"
              : "text-muted-foreground/40 cursor-default",
          )}
        >
          {t("console_blocks.default_color", { defaultValue: "Défaut" })}
        </button>
      </div>
    </div>
  );
}
