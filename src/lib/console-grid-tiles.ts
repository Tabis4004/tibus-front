import { cn } from "@/lib/utils.ts";

export type ConsoleTileStyle = {
  tile: string;
  border: string;
  iconWrap: string;
  icon: string;
  title: string;
};

/** Pastels type Gestabis — une teinte distincte par bloc. */
export const CONSOLE_TILE_PALETTES: ConsoleTileStyle[] = [
  {
    tile: "bg-emerald-50 dark:bg-emerald-950/35",
    border: "border-emerald-200/80 dark:border-emerald-800/45",
    iconWrap: "bg-emerald-400",
    icon: "text-white",
    title: "text-emerald-950 dark:text-emerald-50",
  },
  {
    tile: "bg-amber-50 dark:bg-amber-950/35",
    border: "border-amber-200/80 dark:border-amber-800/45",
    iconWrap: "bg-amber-400",
    icon: "text-white",
    title: "text-amber-950 dark:text-amber-50",
  },
  {
    tile: "bg-sky-50 dark:bg-sky-950/35",
    border: "border-sky-200/80 dark:border-sky-800/45",
    iconWrap: "bg-sky-400",
    icon: "text-white",
    title: "text-sky-950 dark:text-sky-50",
  },
  {
    tile: "bg-teal-50 dark:bg-teal-950/35",
    border: "border-teal-200/80 dark:border-teal-800/45",
    iconWrap: "bg-teal-400",
    icon: "text-white",
    title: "text-teal-950 dark:text-teal-50",
  },
  {
    tile: "bg-rose-50 dark:bg-rose-950/35",
    border: "border-rose-200/80 dark:border-rose-800/45",
    iconWrap: "bg-rose-400",
    icon: "text-white",
    title: "text-rose-950 dark:text-rose-50",
  },
  {
    tile: "bg-violet-50 dark:bg-violet-950/35",
    border: "border-violet-200/80 dark:border-violet-800/45",
    iconWrap: "bg-violet-400",
    icon: "text-white",
    title: "text-violet-950 dark:text-violet-50",
  },
  {
    tile: "bg-orange-50 dark:bg-orange-950/35",
    border: "border-orange-200/80 dark:border-orange-800/45",
    iconWrap: "bg-orange-400",
    icon: "text-white",
    title: "text-orange-950 dark:text-orange-50",
  },
  {
    tile: "bg-cyan-50 dark:bg-cyan-950/35",
    border: "border-cyan-200/80 dark:border-cyan-800/45",
    iconWrap: "bg-cyan-500",
    icon: "text-white",
    title: "text-cyan-950 dark:text-cyan-50",
  },
];

export function consoleTileStyle(index: number): ConsoleTileStyle {
  return CONSOLE_TILE_PALETTES[((index % CONSOLE_TILE_PALETTES.length) + CONSOLE_TILE_PALETTES.length) % CONSOLE_TILE_PALETTES.length]!;
}

export function consoleTileClass(index: number, ...parts: (keyof ConsoleTileStyle)[]): string {
  const style = consoleTileStyle(index);
  return cn(...parts.map((part) => style[part]));
}

/** Modules commerciaux A–F : couleur stable par lettre. */
export function commercialModuleTileIndex(moduleId: string): number {
  const order = "ABCDEF".indexOf(moduleId.toUpperCase());
  return order >= 0 ? order : 0;
}
