import { cn } from "@/lib/utils.ts";

type TibusLogoProps = {
  className?: string;
  alt?: string;
  /** mark = cropped transparent logo for headers; icon = full square app icon */
  variant?: "mark" | "icon";
};

export function TibusLogo({
  className,
  alt = "Tibus",
  variant = "mark",
}: TibusLogoProps) {
  const src =
    variant === "icon" ? "/icon/tibus-icon.png" : "/icon/tibus-mark.png";

  return (
    <img
      src={src}
      alt={alt}
      className={cn("object-contain shrink-0", className)}
      draggable={false}
    />
  );
}
