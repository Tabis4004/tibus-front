import { useCallback, useEffect, useId, useRef, useState } from "react";
import { Html5Qrcode } from "html5-qrcode";
import { CameraIcon, CameraOffIcon, SwitchCameraIcon } from "lucide-react";
import { Button } from "@/components/ui/button.tsx";

type QrScannerProps = {
  onScan: (payload: string) => void;
  paused?: boolean;
};

type CameraFacing = "environment" | "user";

type TibusScannerApi = {
  isAvailable?: () => boolean;
  scan?: () => Promise<string>;
};

function getNativeScanner(): TibusScannerApi | null {
  if (typeof window === "undefined") return null;
  const scanner = (window as Window & { TibusScanner?: TibusScannerApi }).TibusScanner;
  if (scanner?.scan) return scanner;
  return null;
}

function isTibusPosWebView(): boolean {
  if (typeof window === "undefined") return false;
  const w = window as Window & { TibusP3?: unknown; WisePrinter?: unknown; TibusScanner?: unknown };
  return Boolean(w.TibusP3 || w.WisePrinter || w.TibusScanner);
}

function cameraErrorMessage(err: unknown): string {
  const name = err instanceof DOMException ? err.name : "";
  const message = err instanceof Error ? err.message : "";
  if (message === "cancelled" || message === "scan_cancelled") {
    return "Scan annulé.";
  }
  if (message === "camera_permission_denied") {
    return "Accès caméra refusé. Autorisez Tibus dans Paramètres Android → Applications → Tibus → Caméra.";
  }
  if (name === "NotAllowedError" || name === "PermissionDeniedError") {
    return "Accès caméra refusé. Autorisez Tibus dans Paramètres Android → Autorisations → Caméra.";
  }
  if (name === "NotFoundError" || name === "DevicesNotFoundError") {
    return "Aucune caméra détectée sur cet appareil.";
  }
  if (name === "NotReadableError") {
    return "Caméra occupée par une autre application. Fermez les autres apps puis réessayez.";
  }
  if (name === "OverconstrainedError") {
    return "Caméra demandée indisponible. Essayez « Caméra avant » ou « Caméra arrière ».";
  }
  if (!window.isSecureContext && !/^(localhost|127\.0\.0\.1)$/i.test(window.location.hostname)) {
    return "Caméra web bloquée en HTTP. Utilisez le scanner natif Tibus (APK v1.0.2+).";
  }
  if (err instanceof Error && err.message.trim()) return err.message;
  return "Impossible d'accéder à la caméra. Autorisez l'accès dans les paramètres.";
}

const CAMERA_TRY_ORDER: CameraFacing[] = ["user", "environment"];

export default function QrScanner({ onScan, paused = false }: QrScannerProps) {
  const elementId = useId().replace(/:/g, "");
  const scannerRef = useRef<Html5Qrcode | null>(null);
  const [active, setActive] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [nativeScanner] = useState(() => Boolean(getNativeScanner()) || isTibusPosWebView());
  const [facingMode, setFacingMode] = useState<CameraFacing>(
    isTibusPosWebView() ? "user" : "environment",
  );
  const lastScanRef = useRef("");

  const stopScanner = useCallback(async () => {
    const scanner = scannerRef.current;
    scannerRef.current = null;
    if (!scanner) return;
    try {
      if (scanner.isScanning) await scanner.stop();
      await scanner.clear();
    } catch {
      // ignore teardown errors
    }
  }, []);

  const startNativeScanner = useCallback(async () => {
    const native = getNativeScanner();
    if (!native?.scan) return false;

    setError(null);
    setActive(true);
    try {
      const decoded = await native.scan();
      if (paused) {
        setActive(false);
        return true;
      }
      if (!decoded || decoded === lastScanRef.current) {
        setActive(false);
        return true;
      }
      lastScanRef.current = decoded;
      onScan(decoded);
      setActive(false);
      return true;
    } catch (err) {
      setActive(false);
      setError(cameraErrorMessage(err));
      return true;
    }
  }, [onScan, paused]);

  const startWebScanner = useCallback(async () => {
    setError(null);
    await stopScanner();
    const scanner = new Html5Qrcode(elementId);
    scannerRef.current = scanner;

    const configs: CameraFacing[] = [
      facingMode,
      ...CAMERA_TRY_ORDER.filter((mode) => mode !== facingMode),
    ];

    let lastError: unknown = null;
    for (const mode of configs) {
      try {
        await scanner.start(
          { facingMode: mode },
          {
            fps: 10,
            qrbox: { width: 260, height: 260 },
            aspectRatio: 1,
          },
          (decoded: string) => {
            if (paused) return;
            if (!decoded || decoded === lastScanRef.current) return;
            lastScanRef.current = decoded;
            onScan(decoded);
          },
          () => undefined,
        );
        setFacingMode(mode);
        setActive(true);
        return;
      } catch (err) {
        lastError = err;
        try {
          if (scanner.isScanning) await scanner.stop();
          await scanner.clear();
        } catch {
          // ignore
        }
      }
    }

    setActive(false);
    setError(cameraErrorMessage(lastError));
  }, [elementId, facingMode, onScan, paused, stopScanner]);

  const startScanner = useCallback(async () => {
    if (getNativeScanner()) {
      await startNativeScanner();
      return;
    }
    await startWebScanner();
  }, [startNativeScanner, startWebScanner]);

  useEffect(() => {
    return () => {
      void stopScanner();
    };
  }, [stopScanner]);

  useEffect(() => {
    if (paused && active) {
      void stopScanner();
      setActive(false);
    }
  }, [active, paused, stopScanner]);

  const toggleCamera = async () => {
    if (nativeScanner) return;
    const next: CameraFacing = facingMode === "environment" ? "user" : "environment";
    if (active) {
      await stopScanner();
      setActive(false);
    }
    setFacingMode(next);
  };

  return (
    <div className="space-y-4">
      <div className="relative overflow-hidden rounded-2xl border bg-black min-h-[320px]">
        {!nativeScanner ? <div id={elementId} className="w-full min-h-[320px]" /> : null}
        {!active ? (
          <div className={`${nativeScanner ? "" : "absolute inset-0"} flex flex-col items-center justify-center gap-3 bg-black/80 text-white p-6 text-center min-h-[320px]`}>
            <CameraIcon className="w-12 h-12 opacity-80" />
            <p className="text-sm opacity-90">
              {nativeScanner
                ? "Ouvre le scanner natif du TPE pour lire les QR codes des billets."
                : "Activez la caméra pour scanner les QR codes des billets à l'embarquement."}
            </p>
            <Button size="lg" className="cursor-pointer" onClick={() => void startScanner()}>
              <CameraIcon className="w-5 h-5 mr-2" />
              {nativeScanner ? "Scanner un billet" : "Démarrer le scanner"}
            </Button>
          </div>
        ) : nativeScanner ? (
          <div className="flex flex-col items-center justify-center gap-3 bg-black text-white p-6 text-center min-h-[320px]">
            <CameraIcon className="w-12 h-12 opacity-80 animate-pulse" />
            <p className="text-sm opacity-90">Scanner caméra actif…</p>
          </div>
        ) : (
          <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
            <div className="w-[72%] max-w-[280px] aspect-square rounded-2xl border-2 border-white/80 shadow-[0_0_0_9999px_rgba(0,0,0,0.35)]" />
          </div>
        )}
      </div>

      {error ? <p className="text-sm text-red-600 text-center">{error}</p> : null}

      <div className="flex flex-wrap gap-2 justify-center">
        {active && !nativeScanner ? (
          <Button variant="outline" className="cursor-pointer" onClick={() => void stopScanner().then(() => setActive(false))}>
            <CameraOffIcon className="w-4 h-4 mr-2" />
            Arrêter la caméra
          </Button>
        ) : (
          <Button className="cursor-pointer" onClick={() => void startScanner()}>
            <CameraIcon className="w-4 h-4 mr-2" />
            {nativeScanner ? "Scanner un billet" : "Relancer la caméra"}
          </Button>
        )}
        {!nativeScanner ? (
          <Button variant="secondary" className="cursor-pointer" onClick={() => void toggleCamera()}>
            <SwitchCameraIcon className="w-4 h-4 mr-2" />
            {facingMode === "environment" ? "Caméra avant" : "Caméra arrière"}
          </Button>
        ) : null}
      </div>
    </div>
  );
}
