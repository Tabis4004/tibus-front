import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { CopyIcon, PrinterIcon, ScanLineIcon, SmartphoneIcon } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge.tsx";
import { Button } from "@/components/ui/button.tsx";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card.tsx";
import {
  readTibusBridgeFlags,
  subscribeTibusBridges,
  type TibusBridgeFlags,
} from "@/lib/webview-bridge.ts";

const DEFAULT_TPE_PATH = "/fr/seller";

export default function TpePosDiagnosticsPanel() {
  const { t } = useTranslation("admin");
  const [bridges, setBridges] = useState<TibusBridgeFlags>(() => readTibusBridgeFlags());

  useEffect(() => subscribeTibusBridges(setBridges), []);

  const tpeUrl = useMemo(() => {
    if (typeof window === "undefined") return `https://tibus-front.vercel.app${DEFAULT_TPE_PATH}`;
    return `${window.location.origin}${DEFAULT_TPE_PATH}`;
  }, []);

  const refresh = () => setBridges(readTibusBridgeFlags());

  const copyUrl = async () => {
    try {
      await navigator.clipboard.writeText(tpeUrl);
      toast.success(t("tpe.copy_ok", { defaultValue: "URL TPE copiée" }));
    } catch {
      toast.error(t("tpe.copy_error", { defaultValue: "Copie impossible" }));
    }
  };

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between gap-3">
        <CardTitle className="flex items-center gap-2 text-base">
          <SmartphoneIcon className="size-4" />
          {t("tpe.title", { defaultValue: "Terminal TPE (Android)" })}
        </CardTitle>
        <Button type="button" variant="outline" size="sm" onClick={refresh}>
          {t("tpe.refresh", { defaultValue: "Actualiser" })}
        </Button>
      </CardHeader>
      <CardContent className="space-y-4 text-sm">
        <p className="text-muted-foreground">
          {t("tpe.description", {
            defaultValue:
              "L’APK release ouvre cette URL en plein écran. Le HUD debug natif n’apparaît que sur l’APK debug (développement).",
          })}
        </p>
        <div className="rounded-md border bg-muted/40 p-3 font-mono text-xs break-all">{tpeUrl}</div>
        <div className="flex flex-wrap gap-2">
          <Button type="button" variant="secondary" size="sm" onClick={copyUrl}>
            <CopyIcon className="mr-1 size-3.5" />
            {t("tpe.copy_url", { defaultValue: "Copier l’URL TPE" })}
          </Button>
        </div>
        <div className="space-y-2">
          <p className="font-medium">{t("tpe.bridges", { defaultValue: "Ponts natifs (cette session)" })}</p>
          <div className="flex flex-wrap gap-2">
            <Badge variant={bridges.posWebView ? "default" : "secondary"}>
              {bridges.posWebView
                ? t("tpe.in_pos", { defaultValue: "WebView TPE détectée" })
                : t("tpe.in_browser", { defaultValue: "Navigateur (pas TPE)" })}
            </Badge>
            <Badge variant={bridges.tibusP3 ? "default" : "outline"}>
              <PrinterIcon className="mr-1 size-3" />
              TibusP3
            </Badge>
            <Badge variant={bridges.wisePrinter ? "default" : "outline"}>WisePrinter</Badge>
            <Badge variant={bridges.tibusScanner ? "default" : "outline"}>
              <ScanLineIcon className="mr-1 size-3" />
              Scanner
            </Badge>
            <Badge variant={bridges.tibusAuth ? "default" : "outline"}>TibusAuth</Badge>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
