function bytesToUuid(bytes: Uint8Array): string {
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function randomUUIDFallback(): string {
  const bytes = new Uint8Array(16);
  if (typeof globalThis.crypto?.getRandomValues === "function") {
    globalThis.crypto.getRandomValues(bytes);
  } else {
    for (let i = 0; i < 16; i++) bytes[i] = Math.floor(Math.random() * 256);
  }

  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  return bytesToUuid(bytes);
}

/** UUID v4 — fallback for Android WebView over HTTP (no crypto.randomUUID). */
export function randomUUID(): string {
  const native = globalThis.crypto?.randomUUID;
  if (typeof native === "function" && native !== randomUUIDFallback) {
    return native.call(globalThis.crypto);
  }
  return randomUUIDFallback();
}

/** Patch global crypto before app boot (Supabase, forms, etc.). */
export function installRandomUUIDPolyfill(): void {
  const g = globalThis as typeof globalThis & { crypto?: Crypto };
  if (!g.crypto) g.crypto = {} as Crypto;

  if (typeof g.crypto.randomUUID !== "function") {
    g.crypto.randomUUID = randomUUIDFallback as Crypto["randomUUID"];
  }

  if (typeof g.crypto.getRandomValues !== "function") {
    g.crypto.getRandomValues = <T extends ArrayBufferView>(array: T): T => {
      const view = array as unknown as { length: number; [index: number]: number };
      for (let i = 0; i < view.length; i++) view[i] = Math.floor(Math.random() * 256);
      return array;
    };
  }
}
