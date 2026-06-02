export type PrintAlign = "left" | "center" | "right";
export type PrintSize = "small" | "normal" | "large";

export interface PrintLine {
  text: string;
  align?: PrintAlign;
  size?: PrintSize;
  bold?: boolean;
}

export interface Receipt {
  header?: string;
  lines: PrintLine[];
  qr?: string;
  qrSize?: number;
  feedLines?: number;
  cut?: boolean;
}

interface NativeResult {
  ok: boolean;
  error?: string;
  data?: unknown;
}

interface WisePrinterNative {
  isNative: true;
  init: () => Promise<NativeResult>;
  printText: (
    text: string,
    opts?: { align?: PrintAlign; size?: PrintSize; bold?: boolean },
  ) => Promise<NativeResult>;
  printQRCode: (content: string, sizePx?: number) => Promise<NativeResult>;
  feed: (lines: number) => Promise<NativeResult>;
  cut: () => Promise<NativeResult>;
  status: () => Promise<NativeResult>;
}

declare global {
  interface Window {
    WisePrinter?: WisePrinterNative;
  }
}

function native(): WisePrinterNative | null {
  if (typeof window === "undefined") return null;
  return window.WisePrinter ?? null;
}

export const printer = {
  get isNative(): boolean {
    return native() !== null;
  },

  async init(): Promise<void> {
    const n = native();
    if (n) {
      const r = await n.init();
      if (!r.ok) throw new Error(r.error || "Printer init failed");
    }
  },

  async printReceipt(receipt: Receipt): Promise<void> {
    const n = native();
    if (!n) {
      printInBrowser(receipt);
      return;
    }
    if (receipt.header) {
      await must(
        n.printText(receipt.header + "\n", {
          align: "center",
          size: "large",
          bold: true,
        }),
      );
    }
    for (const line of receipt.lines) {
      await must(
        n.printText(line.text + "\n", {
          align: line.align ?? "left",
          size: line.size ?? "normal",
          bold: line.bold ?? false,
        }),
      );
    }
    if (receipt.qr)
      await must(n.printQRCode(receipt.qr, receipt.qrSize ?? 240));
    await must(n.feed(receipt.feedLines ?? 3));
    if (receipt.cut !== false) await must(n.cut());
  },

  async status(): Promise<NativeResult | null> {
    const n = native();
    return n ? n.status() : null;
  },
};

async function must(p: Promise<NativeResult>): Promise<void> {
  const r = await p;
  if (!r.ok) throw new Error(r.error || "Printer error");
}

const ESC_MAP: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ESC_MAP[c] ?? c);
}

function sizeCss(s?: PrintSize): string {
  if (s === "large") return "18px";
  if (s === "small") return "10px";
  return "13px";
}

function printInBrowser(receipt: Receipt): void {
  if (typeof window === "undefined" || typeof document === "undefined") return;
  const w = window.open("", "_blank", "width=380,height=600");
  if (!w) {
    window.print();
    return;
  }
  const body = receipt.lines
    .map(
      (l) =>
        `<div style="text-align:${l.align ?? "left"};font-size:${sizeCss(l.size)};font-weight:${l.bold ? "700" : "400"}">${esc(l.text)}</div>`,
    )
    .join("");
  const headerHtml = receipt.header
    ? `<h2 style="text-align:center;margin:0 0 8px">${esc(receipt.header)}</h2>`
    : "";
  const qrHtml = receipt.qr
    ? `<div style="text-align:center;margin-top:12px"><img alt="qr" src="https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(receipt.qr)}"/></div>`
    : "";
  w.document.write(
    `<!doctype html><html><head><meta charset="utf-8"><title>Receipt</title>
    <style>body{font-family:ui-monospace,monospace;padding:12px;width:300px}</style></head><body>
    ${headerHtml}${body}${qrHtml}
    <script>window.onload=()=>{window.print();setTimeout(()=>window.close(),300);}</script></body></html>`,
  );
  w.document.close();
}
