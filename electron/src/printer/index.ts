import { ipcMain } from "electron";
import * as esc from "./escpos-commands";
import { createTransport, type PrinterTransport } from "./transport";

export interface NativeResult {
  ok: boolean;
  error?: string;
  data?: unknown;
}

type PrintAlign = "left" | "center" | "right";
type PrintSize = "small" | "normal" | "large";

let transport: PrinterTransport | null = null;
let opened = false;

async function ensureOpen(): Promise<PrinterTransport> {
  if (!transport) transport = createTransport();
  if (!opened) {
    await transport.open();
    opened = true;
  }
  return transport;
}

async function ok(data?: unknown): Promise<NativeResult> {
  return { ok: true, data };
}

function fail(error: unknown): NativeResult {
  return { ok: false, error: error instanceof Error ? error.message : String(error) };
}

async function handleInit(): Promise<NativeResult> {
  try {
    const t = await ensureOpen();
    await t.write(esc.cmdInit());
    return ok();
  } catch (e) {
    return fail(e);
  }
}

async function handlePrintText(
  _evt: unknown,
  text: string,
  opts?: { align?: PrintAlign; size?: PrintSize; bold?: boolean },
): Promise<NativeResult> {
  try {
    const t = await ensureOpen();
    const buf = Buffer.concat([
      esc.cmdAlign(opts?.align ?? "left"),
      esc.cmdSize(opts?.size ?? "normal"),
      esc.cmdBold(Boolean(opts?.bold)),
      esc.cmdText(text),
      esc.cmdBold(false),
    ]);
    await t.write(buf);
    return ok();
  } catch (e) {
    return fail(e);
  }
}

async function handlePrintQRCode(_evt: unknown, content: string, sizePx?: number): Promise<NativeResult> {
  try {
    const t = await ensureOpen();
    await t.write(esc.cmdAlign("center"));
    await t.write(esc.cmdQrCode(content, sizePx));
    await t.write(esc.cmdAlign("left"));
    return ok();
  } catch (e) {
    return fail(e);
  }
}

async function handleFeed(_evt: unknown, lines: number): Promise<NativeResult> {
  try {
    const t = await ensureOpen();
    await t.write(esc.cmdFeed(lines));
    return ok();
  } catch (e) {
    return fail(e);
  }
}

async function handleCut(): Promise<NativeResult> {
  try {
    const t = await ensureOpen();
    await t.write(esc.cmdCut());
    return ok();
  } catch (e) {
    return fail(e);
  }
}

async function handleStatus(): Promise<NativeResult> {
  try {
    await ensureOpen();
    return ok({ transport: process.env.PRINTER_TRANSPORT ?? "usb", opened });
  } catch (e) {
    return fail(e);
  }
}

/**
 * À appeler une fois depuis electron/src/index.ts (process main), après app.whenReady().
 * Câble les opérations IPC consommées par le preload (window.WisePrinter).
 */
export function registerPrinterIpc(): void {
  ipcMain.handle("printer:init", handleInit);
  ipcMain.handle("printer:printText", handlePrintText);
  ipcMain.handle("printer:printQRCode", handlePrintQRCode);
  ipcMain.handle("printer:feed", handleFeed);
  ipcMain.handle("printer:cut", handleCut);
  ipcMain.handle("printer:status", handleStatus);
}
