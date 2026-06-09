import { createRoot } from "react-dom/client";
import { initTibusWebView } from "./lib/webview-bridge.ts";
import App from "./App.tsx";
import { ErrorBoundary } from "./components/ErrorBoundary.tsx";

initTibusWebView();

createRoot(document.getElementById("root")!).render(
  <ErrorBoundary>
    <App />
  </ErrorBoundary>,
);
