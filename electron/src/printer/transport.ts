// Couche de transport — envoie les trames ESC/POS à l'imprimante physique.
// Le transport est choisi via la variable d'env PRINTER_TRANSPORT (cf. README.md
// de ce dossier). Les dépendances (usb / serialport) sont chargées à la demande
// (require paresseux) pour ne pas casser le build si elles ne sont pas installées.

export interface PrinterTransport {
  open(): Promise<void>;
  write(buf: Buffer): Promise<void>;
  close?(): Promise<void>;
}

const CUT_SEQUENCE = Buffer.from([0x1d, 0x56, 0x00]); // GS V 0, cf. escpos-commands.ts cmdCut()

/**
 * Transport USB générique (imprimante thermique vue comme périphérique USB).
 * Nécessite le package "usb" (npm i usb --save) dans electron/.
 * Configuration via PRINTER_USB_VID / PRINTER_USB_PID (hex, ex: "04b8" / "0e15").
 */
export class UsbTransport implements PrinterTransport {
  private device: any;
  private iface: any;
  private outEndpoint: any;

  async open(): Promise<void> {
    // require paresseux : évite d'imposer la dépendance native si on utilise un autre transport.
    const usb = require("usb");
    const vid = parseInt(process.env.PRINTER_USB_VID ?? "0", 16);
    const pid = parseInt(process.env.PRINTER_USB_PID ?? "0", 16);
    if (!vid || !pid) {
      throw new Error(
        "PRINTER_USB_VID / PRINTER_USB_PID non définis. Renseignez le VID:PID de l'imprimante (voir README).",
      );
    }
    this.device = usb.findByIds(vid, pid);
    if (!this.device) {
      throw new Error(`Imprimante USB introuvable pour VID=${process.env.PRINTER_USB_VID} PID=${process.env.PRINTER_USB_PID}`);
    }
    this.device.open();
    this.iface = this.device.interfaces[0];
    if (this.iface.isKernelDriverActive()) {
      this.iface.detachKernelDriver();
    }
    this.iface.claim();
    this.outEndpoint = this.iface.endpoints.find((e: any) => e.direction === "out");
    if (!this.outEndpoint) {
      throw new Error("Aucun endpoint OUT trouvé sur l'interface USB de l'imprimante.");
    }
  }

  write(buf: Buffer): Promise<void> {
    return new Promise((resolve, reject) => {
      this.outEndpoint.transfer(buf, (err: unknown) => (err ? reject(err) : resolve()));
    });
  }

  async close(): Promise<void> {
    try {
      this.iface?.release(true, () => {});
      this.device?.close();
    } catch {
      // best-effort
    }
  }
}

/**
 * Transport série/RS232 (ou USB-vers-série virtuel exposé en COMx sous Windows).
 * Nécessite le package "serialport" (npm i serialport --save) dans electron/.
 * Configuration via PRINTER_SERIAL_PATH (ex: "COM3") et PRINTER_SERIAL_BAUD (def. 9600).
 */
export class SerialTransport implements PrinterTransport {
  private port: any;

  async open(): Promise<void> {
    const { SerialPort } = require("serialport");
    const path = process.env.PRINTER_SERIAL_PATH;
    if (!path) {
      throw new Error("PRINTER_SERIAL_PATH non défini (ex: COM3). Voir README.");
    }
    this.port = new SerialPort({
      path,
      baudRate: Number(process.env.PRINTER_SERIAL_BAUD ?? 9600),
    });
    await new Promise<void>((resolve, reject) => {
      this.port.once("open", () => resolve());
      this.port.once("error", reject);
    });
  }

  write(buf: Buffer): Promise<void> {
    return new Promise((resolve, reject) => {
      this.port.write(buf, (err: unknown) => (err ? reject(err) : this.port.drain(() => resolve())));
    });
  }

  async close(): Promise<void> {
    await new Promise<void>((resolve) => this.port?.close(() => resolve()));
  }
}

/**
 * Impression RAW via le spouleur Windows (winspool), en ciblant le pilote
 * déjà installé pour l'imprimante ticket (ex: Xprinter XP-58/XP-80, une
 * fois son pilote Windows installé — voir
 * https://www.xprintertech.com/drivers-2.html).
 *
 * C'est l'intégration recommandée pour Xprinter sous Windows : leur SDK
 * "natif" (DLL) n'est fourni que sur demande auprès du support Xprinter,
 * alors que le pilote Windows générique (installé via leur .exe) suffit à
 * recevoir des trames ESC/POS brutes envoyées en job d'impression de type
 * RAW — aucune compilation native ni DLL propriétaire à intégrer ici.
 *
 * Nécessite le package "printer" (npm i printer --save) dans electron/ —
 * addon natif (node-gyp), à builder avec les Visual Studio Build Tools sur
 * la machine Windows cible (voir README de ce dossier).
 * Configuration : PRINTER_WINDOWS_NAME (nom exact de l'imprimante tel
 * qu'affiché dans Windows > Imprimantes et scanners, ex: "XP-58").
 */
export class WindowsSpoolTransport implements PrinterTransport {
  private printerName = "";
  private buffered: Buffer[] = [];

  async open(): Promise<void> {
    const name = process.env.PRINTER_WINDOWS_NAME;
    if (!name) {
      throw new Error(
        "PRINTER_WINDOWS_NAME non défini. Renseignez le nom exact de l'imprimante Xprinter " +
          "tel qu'affiché dans Windows > Imprimantes et scanners (voir README).",
      );
    }
    this.printerName = name;
    this.buffered = [];
  }

  // Un job d'impression RAW winspool part en un seul bloc (contrairement à
  // USB/série qui acceptent des écritures incrémentales) : on accumule les
  // trames d'un même reçu, puis on soumet le job dès qu'on détecte la
  // commande de coupe (cut()), qui marque la fin du reçu dans
  // src/lib/printer.ts::printReceipt(). close() sert de filet de sécurité
  // si un reçu est imprimé avec cut:false (ne devrait pas arriver en usage
  // normal).
  async write(buf: Buffer): Promise<void> {
    this.buffered.push(buf);
    if (buf.includes(CUT_SEQUENCE)) await this.flush();
  }

  async close(): Promise<void> {
    await this.flush();
  }

  private async flush(): Promise<void> {
    if (this.buffered.length === 0) return;
    const data = Buffer.concat(this.buffered);
    this.buffered = [];
    const printerLib = require("printer");
    await new Promise<void>((resolve, reject) => {
      printerLib.printDirect({
        data,
        printer: this.printerName,
        type: "RAW",
        success: () => resolve(),
        error: (err: unknown) => reject(err instanceof Error ? err : new Error(String(err))),
      });
    });
  }
}

/**
 * Point d'extension pour le SDK fournisseur (DLL / SDK propriétaire du
 * fabricant de l'imprimante). Voir electron/src/printer/vendor-sdk/.
 */
export class VendorSdkTransport implements PrinterTransport {
  async open(): Promise<void> {
    const vendor = require("./vendor-sdk");
    if (typeof vendor.open === "function") return vendor.open();
    throw new Error(
      "Transport 'vendor' sélectionné mais electron/src/printer/vendor-sdk/index.ts n'implémente pas encore open(). " +
        "Déposez le SDK fournisseur dans ce dossier (voir README) puis implémentez open()/write()/close().",
    );
  }

  async write(buf: Buffer): Promise<void> {
    const vendor = require("./vendor-sdk");
    if (typeof vendor.write === "function") return vendor.write(buf);
    throw new Error("vendor-sdk/index.ts: write() non implémenté.");
  }

  async close(): Promise<void> {
    const vendor = require("./vendor-sdk");
    if (typeof vendor.close === "function") return vendor.close();
  }
}

export function createTransport(): PrinterTransport {
  const kind = (process.env.PRINTER_TRANSPORT ?? "usb").toLowerCase();
  if (kind === "serial") return new SerialTransport();
  if (kind === "vendor") return new VendorSdkTransport();
  if (kind === "windows" || kind === "xprinter") return new WindowsSpoolTransport();
  return new UsbTransport();
}
