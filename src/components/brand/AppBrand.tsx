import { Link, type LinkProps } from "react-router-dom";
import { cn } from "@/lib/utils.ts";
import { APP_NAME } from "@/lib/brand.ts";
import { TibusLogo } from "./TibusLogo.tsx";

type AppBrandProps = {
  to?: LinkProps["to"];
  className?: string;
  logoClassName?: string;
  titleClassName?: string;
  onClick?: () => void;
};

export function AppBrand({
  to,
  className,
  logoClassName = "h-9 w-9",
  titleClassName,
  onClick,
}: AppBrandProps) {
  const content = (
    <>
      <TibusLogo variant="mark" className={logoClassName} />
      <span className={cn("font-extrabold tracking-tight", titleClassName)}>{APP_NAME}</span>
    </>
  );

  if (to != null) {
    return (
      <Link to={to} onClick={onClick} className={cn("flex items-center gap-2", className)}>
        {content}
      </Link>
    );
  }

  return (
    <div className={cn("flex items-center gap-2", className)} onClick={onClick}>
      {content}
    </div>
  );
}
