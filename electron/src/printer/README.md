# Pont imprimante native (Windows)

Ce dossier implémente le bridge `window.WisePrinter` côté desktop (Electron),
avec exactement la même interface que celle déjà attendue par l'app web
(`src/lib/printer.ts` à la racine du projet, côté `tibus-front`). **Aucune
modification du code web n'est nécessaire** : dès que ce bridge est présent
dans la fenêtre, l'app l'utilise automatiquement pour imprimer les
tickets/reçus ; sinon elle retombe sur `window.print()`.

## Architecture

```
electron/src/preload.ts          -> expose window.WisePrinter (contextBridge)
electron/src/printer/index.ts    -> handlers IPC ("printer:init", "printer:printText", ...)
electron/src/printer/escpos-commands.ts -> construction des trames ESC/POS (pur JS)
electron/src/printer/transport.ts -> USB / Série / SDK fournisseur (transport physique)
electron/src/printer/vendor-sdk/ -> emplacement réservé au SDK propriétaire fourni
```

Les 6 opérations exposées (`init`, `printText`, `printQRCode`, `feed`, `cut`,
`status`) construisent des trames ESC/POS standard (compatibles avec la
quasi-totalité des imprimantes tickets thermiques : Epson, Xprinter, Gprinter,
Rongta, Bixolon en mode générique, etc.) puis les envoient via le transport
sélectionné.

## Choisir le transport

Variable d'environnement `PRINTER_TRANSPORT` (à définir avant de lancer
l'app Electron, ex. dans `electron/.env` chargé par votre process de build/
lancement, ou directement dans l'environnement Windows) :

| Valeur     | Description                                            | Dépendance npm à ajouter dans `electron/` |
|------------|---------------------------------------------------------|--------------------------------------------|
| `usb`      | Imprimante vue comme périphérique USB (défaut)          | `npm i usb`                                 |
| `serial`   | Port série / COMx (RS232 ou USB-série virtuel)           | `npm i serialport`                          |
| `windows`  | Spouleur Windows (pilote déjà installé) — **recommandé pour Xprinter** | `npm i printer`     |
| `vendor`   | SDK propriétaire du fabricant (DLL fournie sur demande)  | dépend du SDK fourni (voir ci-dessous)      |

Config complémentaire :
- USB : `PRINTER_USB_VID`, `PRINTER_USB_PID` (hex, sans préfixe, ex. `04b8` / `0e15`)
  — visibles dans le Gestionnaire de périphériques Windows ou via `lsusb`/`usb-devices`.
- Série : `PRINTER_SERIAL_PATH` (ex. `COM3`), `PRINTER_SERIAL_BAUD` (défaut `9600`).
- Windows/Xprinter : `PRINTER_WINDOWS_NAME` (nom exact de l'imprimante dans Windows, ex. `XP-58`).

## Imprimante Xprinter sous Windows (guichet)

Xprinter (https://www.xprintertech.com) ne fournit sa vraie DLL SDK que sur
demande auprès de leur support — inutile de l'attendre pour imprimer : leurs
imprimantes s'installent comme une imprimante Windows standard, et acceptent
des trames ESC/POS brutes envoyées en job d'impression RAW via le spouleur.
C'est ce que fait le transport `windows` (`electron/src/printer/transport.ts`,
classe `WindowsSpoolTransport`) — pas de DLL propriétaire à intégrer.

Étapes :
1. Installer le pilote Windows de l'imprimante : https://www.xprintertech.com/drivers-2.html
   (choisir le modèle exact, ex. XP-58 / XP-80), puis la brancher en USB.
2. Noter le nom exact tel qu'affiché dans **Windows > Imprimantes et
   scanners** (ex. `XP-58`).
3. Dans `electron/` : `npm i printer` (addon natif — nécessite les Visual
   Studio Build Tools sur la machine Windows, comme `node-gyp` en général).
4. Définir les variables d'environnement avant de lancer l'app :
   ```
   PRINTER_TRANSPORT=windows
   PRINTER_WINDOWS_NAME=XP-58
   ```
5. Lancer/rebuild l'app Electron (`npm run electron:start`) — `printReceipt()`
   côté web (`src/lib/printer.ts`) fonctionne sans aucune modification.

Si un jour vous obtenez la vraie DLL Xprinter (ex. pour piloter un tiroir-
caisse ou une balance intégrée), déposez-la dans `vendor-sdk/` et basculez
sur `PRINTER_TRANSPORT=vendor` — voir section suivante.

## Intégrer le SDK fournisseur (quand vous aurez les fichiers)

1. Déposez les fichiers du SDK (DLL, package npm du fabricant, ou exécutable)
   dans `electron/src/printer/vendor-sdk/`.
2. Implémentez `open()`, `write(buf: Buffer)`, `close()` dans
   `electron/src/printer/vendor-sdk/index.ts` :
   - **DLL .NET/native Windows** → utilisez `koffi` ou `ffi-napi` pour
     appeler les fonctions exportées (`npm i koffi` dans `electron/`).
   - **Package npm du fabricant** → `npm i <package-fournisseur>` puis
     appelez-le directement, en transformant le `Buffer` ESC/POS reçu (ou
     en utilisant les méthodes haut-niveau du SDK si celui-ci propose déjà
     ses propres primitives texte/QR/cut — dans ce cas, vous pouvez aussi
     adapter directement `electron/src/printer/index.ts` pour appeler le
     SDK plutôt que de passer par les trames ESC/POS).
   - **Exécutable/CLI fournisseur** → invoquez-le via `child_process.exec`
     ou `execFile`, en lui passant les données à imprimer (fichier temp ou
     stdin selon ce que prévoit le CLI).
3. Définissez `PRINTER_TRANSPORT=vendor` pour activer ce transport.

Tant que `vendor-sdk/index.ts` n'est pas rempli, ce transport renvoie une
erreur explicite (visible côté web via `r.error`) plutôt que d'échouer
silencieusement.

## Test rapide (sans imprimante)

`status()` n'écrit qu'une trame d'init et retourne le transport actif —
utile pour vérifier le câblage IPC sans déclencher de vraie impression
papier coûteuse pendant les tests.
