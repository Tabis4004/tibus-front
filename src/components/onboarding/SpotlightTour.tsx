import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from "react";
import { createPortal } from "react-dom";
import { useTranslation } from "react-i18next";
import { ArrowLeftIcon, ArrowRightIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";
import type { TourStepConfig } from "@/lib/onboarding-tours.ts";

type Rect = {
  top: number;
  left: number;
  width: number;
  height: number;
};

type TooltipPlacement = "top" | "bottom" | "left" | "right";

type SpotlightTourProps = {
  open: boolean;
  steps: TourStepConfig[];
  onComplete: () => Promise<void>;
  onStart?: () => void;
  onStepChange?: (step: TourStepConfig, index: number) => void;
};

const SAFE_TOP = 56;
const SAFE_BOTTOM = 88;
const SAFE_SIDE = 12;
const TOOLTIP_ESTIMATE = { width: 300, height: 200 };

function measureTarget(selector: string): Rect | null {
  const el = document.querySelector(selector);
  if (!el) return null;
  const box = el.getBoundingClientRect();
  if (box.width <= 0 && box.height <= 0) return null;
  const pad = 6;
  return {
    top: box.top - pad,
    left: box.left - pad,
    width: box.width + pad * 2,
    height: box.height + pad * 2,
  };
}

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max);
}

function resolveTooltipPlacement(
  rect: Rect,
  preferred: TooltipPlacement,
): { placement: TooltipPlacement; style: React.CSSProperties } {
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const margin = 14;
  const tw = TOOLTIP_ESTIMATE.width;
  const th = TOOLTIP_ESTIMATE.height;

  const candidates: TooltipPlacement[] = [
    preferred,
    "bottom",
    "top",
    "right",
    "left",
  ];

  const uniqueCandidates = [...new Set(candidates)];

  for (const placement of uniqueCandidates) {
    let top = 0;
    let left = 0;
    let transform = "";

    switch (placement) {
      case "left":
        top = rect.top + rect.height / 2;
        left = rect.left - margin;
        transform = "translate(-100%, -50%)";
        break;
      case "top":
        top = rect.top - margin;
        left = rect.left + rect.width / 2;
        transform = "translate(-50%, -100%)";
        break;
      case "bottom":
        top = rect.top + rect.height + margin;
        left = rect.left + rect.width / 2;
        transform = "translate(-50%, 0)";
        break;
      case "right":
      default:
        top = rect.top + rect.height / 2;
        left = rect.left + rect.width + margin;
        transform = "translateY(-50%)";
        break;
    }

    const box = estimateTooltipBox(top, left, transform, tw, th);
    const fits =
      box.left >= SAFE_SIDE &&
      box.top >= SAFE_TOP &&
      box.right <= vw - SAFE_SIDE &&
      box.bottom <= vh - SAFE_BOTTOM;

    if (fits) {
      return {
        placement,
        style: {
          position: "fixed",
          zIndex: 10002,
          maxWidth: "min(320px, calc(100vw - 24px))",
          top,
          left,
          transform,
        },
      };
    }
  }

  const centeredTop = clamp(
    rect.top + rect.height + margin,
    SAFE_TOP,
    vh - SAFE_BOTTOM - th,
  );
  const centeredLeft = clamp(
    rect.left + rect.width / 2,
    SAFE_SIDE + tw / 2,
    vw - SAFE_SIDE - tw / 2,
  );

  return {
    placement: "bottom",
    style: {
      position: "fixed",
      zIndex: 10002,
      maxWidth: "min(320px, calc(100vw - 24px))",
      top: centeredTop,
      left: centeredLeft,
      transform: "translateX(-50%)",
    },
  };
}

function estimateTooltipBox(
  top: number,
  left: number,
  transform: string,
  width: number,
  height: number,
) {
  let x = left;
  let y = top;

  if (transform.includes("translate(-50%")) x -= width / 2;
  if (transform.includes("-100%")) x -= width;
  if (transform.includes("-50%)") && transform.includes("translateY")) y -= height / 2;
  if (transform.includes("-100%)") && transform.includes("translate(-50%")) y -= height;

  return {
    left: x,
    top: y,
    right: x + width,
    bottom: y + height,
  };
}

function isOwnerSidebarTarget(selector: string) {
  return selector.includes('data-tour="owner-');
}

export default function SpotlightTour({
  open,
  steps,
  onComplete,
  onStart,
  onStepChange,
}: SpotlightTourProps) {
  const { t } = useTranslation("common");
  const [stepIndex, setStepIndex] = useState(0);
  const [rect, setRect] = useState<Rect | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [started, setStarted] = useState(false);
  const tooltipRef = useRef<HTMLDivElement>(null);
  const nextButtonRef = useRef<HTMLButtonElement>(null);

  const step = steps[stepIndex];
  const isLast = stepIndex === steps.length - 1;
  const placement = step?.placement ?? "right";

  const ensureOwnerSidebarOpen = useCallback((currentStep: TourStepConfig | undefined) => {
    if (!currentStep || !isOwnerSidebarTarget(currentStep.target)) return;
    window.dispatchEvent(
      new CustomEvent("tibus:owner-sidebar", { detail: { open: true } }),
    );
  }, []);

  const refreshRect = useCallback(() => {
    if (!step) return;

    ensureOwnerSidebarOpen(step);
    const target = document.querySelector(step.target);
    target?.scrollIntoView({ block: "center", inline: "nearest", behavior: "smooth" });

    let attempts = 0;
    const tryMeasure = () => {
      const next = measureTarget(step.target);
      if (next) {
        setRect(next);
        return;
      }
      attempts += 1;
      if (attempts < 12) {
        window.setTimeout(tryMeasure, 80);
      }
    };

    window.requestAnimationFrame(tryMeasure);
  }, [ensureOwnerSidebarOpen, step]);

  useEffect(() => {
    if (!open) {
      setStepIndex(0);
      setRect(null);
      setStarted(false);
      return;
    }
    onStart?.();
    setStarted(true);
  }, [open, onStart]);

  useEffect(() => {
    if (!open || !step) return;
    onStepChange?.(step, stepIndex);
    setRect(null);
    refreshRect();
  }, [open, step, stepIndex, refreshRect, onStepChange]);

  useLayoutEffect(() => {
    if (!open || !started || !step) return;

    const onResize = () => refreshRect();
    window.addEventListener("resize", onResize);
    window.addEventListener("scroll", onResize, true);
    return () => {
      window.removeEventListener("resize", onResize);
      window.removeEventListener("scroll", onResize, true);
    };
  }, [open, started, step, stepIndex, refreshRect]);

  useEffect(() => {
    if (!open || !step) return;
    const timer = window.setInterval(refreshRect, 400);
    return () => window.clearInterval(timer);
  }, [open, step, stepIndex, refreshRect]);

  const handleFinish = useCallback(async () => {
    setIsSaving(true);
    try {
      await onComplete();
    } finally {
      setIsSaving(false);
    }
  }, [onComplete]);

  const goNext = useCallback(() => {
    if (isLast) {
      void handleFinish();
      return;
    }
    setStepIndex((i) => Math.min(steps.length - 1, i + 1));
  }, [handleFinish, isLast, steps.length]);

  const goPrev = useCallback(() => {
    setStepIndex((i) => Math.max(0, i - 1));
  }, []);

  useEffect(() => {
    if (!open || !step) return;

    const onKeyDown = (event: KeyboardEvent) => {
      const tag = (event.target as HTMLElement | null)?.tagName?.toLowerCase();
      const typing = tag === "input" || tag === "textarea" || tag === "select";

      if (event.key === "ArrowRight" || event.key === "ArrowDown") {
        event.preventDefault();
        if (!isSaving) goNext();
        return;
      }

      if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
        event.preventDefault();
        if (!isSaving && stepIndex > 0) goPrev();
        return;
      }

      if (event.key === "Enter" && !typing) {
        event.preventDefault();
        if (!isSaving) goNext();
        return;
      }

      if (event.key === "Escape") {
        event.preventDefault();
        void handleFinish();
      }
    };

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [open, step, goNext, goPrev, handleFinish, isSaving, stepIndex]);

  useEffect(() => {
    if (!open || !rect) return;
    const timer = window.setTimeout(() => nextButtonRef.current?.focus(), 80);
    return () => window.clearTimeout(timer);
  }, [open, rect, stepIndex]);

  if (!open || !step) return null;

  const tooltip = rect
    ? resolveTooltipPlacement(rect, placement)
    : {
        placement: "bottom" as TooltipPlacement,
        style: {
          position: "fixed" as const,
          zIndex: 10002,
          maxWidth: "min(320px, calc(100vw - 24px))",
          top: "50%",
          left: "50%",
          transform: "translate(-50%, -50%)",
        },
      };

  return createPortal(
    <div className="fixed inset-0 z-[10000]" aria-live="polite" role="dialog" aria-modal="true">
      {rect ? (
        <div
          className="absolute rounded-xl border-2 border-primary shadow-[0_0_0_9999px_rgba(0,0,0,0.62)] pointer-events-none transition-all duration-300 ease-out"
          style={{
            top: Math.max(8, rect.top),
            left: Math.max(8, rect.left),
            width: rect.width,
            height: rect.height,
            zIndex: 10001,
          }}
        />
      ) : (
        <div className="absolute inset-0 bg-black/60 pointer-events-none" style={{ zIndex: 10001 }} />
      )}

      <div
        ref={tooltipRef}
        className="rounded-2xl border-2 border-primary bg-background p-4 shadow-2xl space-y-3 pointer-events-auto"
        style={tooltip.style}
      >
        <div className="space-y-1">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-primary">
            {t("guide.step_label", { defaultValue: "Étape" })} {stepIndex + 1}/{steps.length}
          </p>
          <h3 className="text-base font-bold text-foreground">
            {t(step.titleKey, { defaultValue: step.titleDefault })}
          </h3>
          <p className="text-sm text-muted-foreground leading-relaxed">
            {t(step.descKey, { defaultValue: step.descDefault })}
          </p>
          <p className="text-[10px] text-muted-foreground/80 pt-1">
            {t("guide.keyboard_hint", {
              defaultValue: "← → ou Tab pour naviguer · Entrée pour continuer · Échap pour fermer",
            })}
          </p>
        </div>

        <div className="flex items-center justify-between gap-2">
          <Button
            type="button"
            variant="ghost"
            size="sm"
            disabled={stepIndex === 0 || isSaving}
            onClick={goPrev}
            className="cursor-pointer gap-1"
          >
            <ArrowLeftIcon className="w-4 h-4" />
            {t("guide.prev", { defaultValue: "Retour" })}
          </Button>
          <Button
            ref={nextButtonRef}
            type="button"
            size="sm"
            disabled={isSaving}
            onClick={goNext}
            className="cursor-pointer gap-1"
          >
            {isLast
              ? t("guide.finish", { defaultValue: "Terminer" })
              : t("guide.next", { defaultValue: "Suivant" })}
            {!isLast && <ArrowRightIcon className="w-4 h-4" />}
          </Button>
        </div>
      </div>
    </div>,
    document.body,
  );
}
