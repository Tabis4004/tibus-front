require('./rt/electron-rt');
//////////////////////////////
// User Defined Preload scripts below

import { contextBridge, ipcRenderer } from 'electron';

// Expose un bridge "WisePrinter" identique à l'interface native attendue par
// src/lib/printer.ts côté web (window.WisePrinter). Aucune modification du
// code de l'app web n'est nécessaire : elle détecte et utilise ce bridge
// automatiquement dès qu'il est présent, sinon elle retombe sur window.print().
contextBridge.exposeInMainWorld('WisePrinter', {
  isNative: true,
  init: () => ipcRenderer.invoke('printer:init'),
  printText: (text: string, opts?: { align?: string; size?: string; bold?: boolean }) =>
    ipcRenderer.invoke('printer:printText', text, opts),
  printQRCode: (content: string, sizePx?: number) => ipcRenderer.invoke('printer:printQRCode', content, sizePx),
  feed: (lines: number) => ipcRenderer.invoke('printer:feed', lines),
  cut: () => ipcRenderer.invoke('printer:cut'),
  status: () => ipcRenderer.invoke('printer:status'),
});

console.log('Tibus printer bridge (WisePrinter) ready.');
