export type NetworkStatus = "online" | "offline";

type Listener = (online: boolean) => void;

const listeners = new Set<Listener>();

function notify() {
  const online = isBrowserOnline();
  for (const listener of listeners) {
    listener(online);
  }
}

export function isBrowserOnline(): boolean {
  if (typeof navigator === "undefined") return true;
  return navigator.onLine;
}

export function subscribeNetworkStatus(listener: Listener): () => void {
  listeners.add(listener);
  if (typeof window !== "undefined") {
    window.addEventListener("online", notify);
    window.addEventListener("offline", notify);
  }
  return () => {
    listeners.delete(listener);
    if (typeof window !== "undefined") {
      window.removeEventListener("online", notify);
      window.removeEventListener("offline", notify);
    }
  };
}
