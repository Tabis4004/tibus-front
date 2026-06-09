export type TibusBridgeFlags = {
  tibusP3: boolean;
  tibusScanner: boolean;
  wisePrinter: boolean;
  tibusAuth: boolean;
  posWebView: boolean;
};

export const TIBUS_BRIDGES_READY_EVENT = "tibus:bridges-ready";

type TibusWindow = Window & {
  TibusP3?: unknown;
  TibusScanner?: { isAvailable?: () => boolean; scan?: () => Promise<string> };
  TibusScannerNative?: { scan?: (callbackId: string) => void };
  WisePrinter?: { isNative?: boolean };
  WisePrinterNative?: unknown;
  TibusAuth?: { googleSignIn?: () => void; googleSignOut?: () => void };
  TibusWeb?: { onSpaNavigation?: (url: string) => void };
  onTibusGoogleAuthSuccess?: (
    idToken: string,
    email: string,
    name: string,
    photoUrl: string,
  ) => void;
  onTibusGoogleAuthError?: (code: string) => void;
  onTibusGoogleSignOut?: () => void;
};

function w(): TibusWindow | null {
  if (typeof window === "undefined") return null;
  return window as TibusWindow;
}

export function readTibusBridgeFlags(): TibusBridgeFlags {
  const win = w();
  if (!win) {
    return {
      tibusP3: false,
      tibusScanner: false,
      wisePrinter: false,
      tibusAuth: false,
      posWebView: false,
    };
  }

  const tibusScanner = Boolean(
    win.TibusScanner?.scan || win.TibusScanner?.isAvailable?.() || win.TibusScannerNative,
  );

  return {
    tibusP3: Boolean(win.TibusP3),
    tibusScanner,
    wisePrinter: Boolean(win.WisePrinter?.isNative ?? win.WisePrinter ?? win.WisePrinterNative),
    tibusAuth: Boolean(win.TibusAuth?.googleSignIn),
    posWebView: Boolean(
      win.TibusP3 ||
        win.TibusScanner ||
        win.WisePrinter ||
        win.TibusAuth ||
        win.TibusScannerNative ||
        win.WisePrinterNative,
    ),
  };
}

export function isTibusPosWebView(): boolean {
  return readTibusBridgeFlags().posWebView;
}

export function notifyNativeSpaNavigation(url?: string) {
  const win = w();
  if (!win) return;
  const href = url ?? win.location.href;
  try {
    win.TibusWeb?.onSpaNavigation?.(href);
  } catch {
    // Native bridge optional (older APK)
  }
}

export function dispatchBridgesReady() {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new CustomEvent(TIBUS_BRIDGES_READY_EVENT, { detail: readTibusBridgeFlags() }));
}

let initDone = false;

export function initTibusWebView() {
  if (typeof document === "undefined" || initDone) return;
  initDone = true;

  document.documentElement.classList.add("tibus-pos-ready");

  const sync = () => {
    if (isTibusPosWebView()) {
      document.documentElement.classList.add("tibus-pos-webview");
      dispatchBridgesReady();
    }
  };

  sync();

  let attempts = 0;
  const timer = window.setInterval(() => {
    attempts += 1;
    sync();
    if (isTibusPosWebView() || attempts >= 24) {
      window.clearInterval(timer);
    }
  }, 250);
}

export function subscribeTibusBridges(onChange: (flags: TibusBridgeFlags) => void): () => void {
  const emit = () => onChange(readTibusBridgeFlags());
  emit();

  const onReady = () => emit();
  window.addEventListener(TIBUS_BRIDGES_READY_EVENT, onReady);

  let attempts = 0;
  const timer = window.setInterval(() => {
    attempts += 1;
    emit();
    if (attempts >= 12) window.clearInterval(timer);
  }, 500);

  return () => {
    window.removeEventListener(TIBUS_BRIDGES_READY_EVENT, onReady);
    window.clearInterval(timer);
  };
}

export function getNativeScanner() {
  const win = w();
  if (!win?.TibusScanner?.scan) return null;
  return win.TibusScanner;
}
