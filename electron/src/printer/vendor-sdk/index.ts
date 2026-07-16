// === Emplacement réservé au SDK fournisseur de l'imprimante ===
//
// Déposez ici les fichiers fournis par le fabricant :
//   - DLL .NET / natif Windows  -> à appeler via "ffi-napi"/"koffi" ou "edge-js"
//   - Package npm du fournisseur -> `npm i <package>` dans electron/, puis l'importer ici
//   - Exécutable / CLI fournisseur -> à invoquer via child_process depuis ce fichier
//
// Ce module doit exposer la même forme que les autres transports
// (electron/src/printer/transport.ts) : open(), write(buf), close().
// Une fois rempli, sélectionnez ce transport avec PRINTER_TRANSPORT=vendor
// (voir electron/.env ou electron/src/printer/README.md).

export async function open(): Promise<void> {
  throw new Error(
    "vendor-sdk non configuré : déposez le SDK fournisseur dans electron/src/printer/vendor-sdk/ " +
      "puis implémentez open() ici.",
  );
}

export async function write(_buf: Buffer): Promise<void> {
  throw new Error("vendor-sdk non configuré : implémentez write(buf) ici (envoi des octets ESC/POS au SDK).");
}

export async function close(): Promise<void> {
  // best-effort par défaut, pas d'erreur si non implémenté.
}
