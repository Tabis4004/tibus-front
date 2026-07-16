import type { CapacitorConfig } from "@capacitor/cli";

// Habillage desktop (Windows) de la SPA tibus-front via Capacitor + Electron.
// webDir pointe sur le build Vite déjà existant (npm run build -> dist/).
// Pas de server.url : on embarque le build statique, les appels Convex/Supabase
// restent distants (l'app fonctionne comme un client desktop classique).
const config: CapacitorConfig = {
  appId: "com.tibus.africa.desktop",
  appName: "Tibus Africa",
  webDir: "dist",
  plugins: {},
};

export default config;
