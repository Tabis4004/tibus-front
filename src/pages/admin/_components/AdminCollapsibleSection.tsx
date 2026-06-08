import type { ReactNode } from "react";
import { Badge } from "@/components/ui/badge.tsx";
import {
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion.tsx";
import { cn } from "@/lib/utils.ts";
import AdminAuditHub from "./AdminAuditHub.tsx";

export default function AdminCollapsibleSection({
  value,
  title,
  count,
  children,
  className,
  auditModuleKey,
}: {
  value: string;
  title: string;
  count?: number;
  children: ReactNode;
  className?: string;
  auditModuleKey?: string;
}) {
  return (
    <AccordionItem
      value={value}
      className={cn(
        "overflow-hidden rounded-lg border border-border bg-card px-3 shadow-none last:border-b",
        className,
      )}
    >
      <AccordionTrigger
        className={cn(
          "min-h-10 py-2 hover:no-underline items-center",
          "[&>svg]:size-4 [&>svg]:shrink-0 [&>svg]:translate-y-0",
          "data-[state=closed]:py-2 data-[state=open]:pb-2 data-[state=open]:pt-2.5",
        )}
      >
        <span className="flex flex-1 items-center gap-2 text-sm font-semibold">
          {title}
          {count !== undefined && (
            <Badge variant="secondary" className="h-5 px-1.5 text-[10px] font-normal tabular-nums">
              {count}
            </Badge>
          )}
        </span>
      </AccordionTrigger>
      <AccordionContent className="space-y-3 border-t pb-3 pt-2">
        {children}
        {auditModuleKey ? <AdminAuditHub moduleKey={auditModuleKey} className="mt-1" /> : null}
      </AccordionContent>
    </AccordionItem>
  );
}
