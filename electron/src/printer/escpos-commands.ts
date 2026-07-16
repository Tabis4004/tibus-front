// Constructeur de trames ESC/POS — pur JS, sans dépendance native.
// Couvre le sous-ensemble utilisé par src/lib/printer.ts (texte, QR, feed, cut).
// Référence: spécification ESC/POS (Epson) — compatible avec la quasi-totalité
// des imprimantes tickets thermiques (Epson, Xprinter, Gprinter, Rongta, etc.)

export type PrintAlign = "left" | "center" | "right";
export type PrintSize = "small" | "normal" | "large";

const ESC = 0x1b;
const GS = 0x1d;

function bytes(...values: number[]): Buffer {
  return Buffer.from(values);
}

export function cmdInit(): Buffer {
  return bytes(ESC, 0x40); // ESC @
}

export function cmdAlign(align: PrintAlign): Buffer {
  const n = align === "center" ? 1 : align === "right" ? 2 : 0;
  return bytes(ESC, 0x61, n); // ESC a n
}

export function cmdBold(on: boolean): Buffer {
  return bytes(ESC, 0x45, on ? 1 : 0); // ESC E n
}

export function cmdSize(size: PrintSize): Buffer {
  // ESC M n -> police A (0) / B (1, plus compacte)
  // GS ! n  -> multiplicateurs largeur/hauteur (nibble haut = largeur-1, nibble bas = hauteur-1)
  const font = size === "small" ? bytes(ESC, 0x4d, 1) : bytes(ESC, 0x4d, 0);
  const mult = size === "large" ? bytes(GS, 0x21, 0x11) : bytes(GS, 0x21, 0x00);
  return Buffer.concat([font, mult]);
}

export function cmdText(text: string): Buffer {
  // CP437/latin1 couvre les accents français dans la plupart des firmwares ESC/POS.
  return Buffer.concat([Buffer.from(text, "latin1"), bytes(0x0a)]);
}

export function cmdFeed(lines: number): Buffer {
  const n = Math.max(0, Math.min(255, Math.round(lines)));
  return bytes(...Array.from({ length: n }, () => 0x0a));
}

export function cmdCut(): Buffer {
  return bytes(GS, 0x56, 0x00); // GS V 0 -> coupe totale
}

/**
 * QR code natif via les commandes GS ( k (imprimé directement par le firmware,
 * aucun encodage bitmap côté app nécessaire).
 */
export function cmdQrCode(content: string, sizePx = 240): Buffer {
  const data = Buffer.from(content, "utf8");
  const moduleSize = Math.max(3, Math.min(12, Math.round(sizePx / 40)));

  const gsk = (pL: number, pH: number, ...rest: number[]) => bytes(GS, 0x28, 0x6b, pL, pH, ...rest);

  const selectModel = gsk(0x04, 0x00, 0x31, 0x41, 0x32, 0x00); // modèle 2
  const setModuleSize = gsk(0x03, 0x00, 0x31, 0x43, moduleSize);
  const setErrorCorrection = gsk(0x03, 0x00, 0x31, 0x45, 0x31); // niveau M

  const storeLen = data.length + 3;
  const storeData = Buffer.concat([
    gsk(storeLen & 0xff, (storeLen >> 8) & 0xff, 0x31, 0x50, 0x30),
    data,
  ]);
  const printQr = gsk(0x03, 0x00, 0x31, 0x51, 0x30);

  return Buffer.concat([selectModel, setModuleSize, setErrorCorrection, storeData, printQr]);
}
