import { useEffect, useState } from "react";
import { useLocation } from "react-router-dom";
import {
  initTibusWebView,
  isTibusPosWebView,
  notifyNativeSpaNavigation,
  readTibusBridgeFlags,
  type TibusBridgeFlags,
} from "@/lib/webview-bridge.ts";

export function useTibusWebViewBootstrap() {
  const location = useLocation();
  const [bridges, setBridges] = useState<TibusBridgeFlags>(() => readTibusBridgeFlags());

  useEffect(() => {
    initTibusWebView();
    const timer = window.setInterval(() => setBridges(readTibusBridgeFlags()), 500);
    const stop = window.setTimeout(() => window.clearInterval(timer), 6000);
    return () => {
      window.clearInterval(timer);
      window.clearTimeout(stop);
    };
  }, []);

  useEffect(() => {
    if (!isTibusPosWebView()) return;
    notifyNativeSpaNavigation(`${window.location.origin}${location.pathname}${location.search}`);
    setBridges(readTibusBridgeFlags());
  }, [location.pathname, location.search]);
}
