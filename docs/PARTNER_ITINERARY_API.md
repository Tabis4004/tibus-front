# API partenaire Tibus — Itinéraires & places disponibles

Documentation d’implémentation pour connecter un système externe (ERP, autre compagnie, agrégateur) à Tibus.

## Vue d’ensemble

```
┌─────────────────┐     clé API      ┌──────────────────────────┐
│ Système externe │ ───────────────► │ partner-itinerary-api    │
└─────────────────┘                  │ (Edge Function Supabase)  │
        ▲                            └────────────┬─────────────┘
        │ webhooks HMAC                           │ RPC SECURITY DEFINER
        └─────────────────────────────────────────┤
                                                  ▼
                                    Gares · Trajets · Départs (Reservations)
                                                  │
                                    Places = capacity − billets émis − holds
```

**Principe** : le partenaire synchronise ses départs vers Tibus. Les ventes créent des billets `ReservationBus` avec `saleChannel = partner_api`. L’inventaire reste **unique** côté Tibus.

---

## Déploiement

### 1. Migrations SQL (ordre)

| Fichier | Contenu |
|---------|---------|
| `082_partner_itinerary_api.sql` | Clés API, mappings gares/départs, sync itinéraires |
| `083_partner_api_bookings_webhooks.sql` | Réservations partenaire, webhooks, disponibilité avec holds |

Exécuter dans le **SQL Editor** Supabase du projet `kqudaqtydimjclwaihqr`.

### 2. Edge Function

```bash
supabase functions deploy partner-itinerary-api --project-ref kqudaqtydimjclwaihqr
```

### 3. Clé API (côté owner Tibus)

1. Console owner → **Opérations → API partenaire** (`/fr/owner/partner-api`)
2. Générer une clé (`tibus_…`) — **affichée une seule fois**
3. Optionnel : configurer un **webhook** (secret `whsec_…`)

---

## Authentification

Toutes les routes (sauf `/v1/health`) exigent une clé API :

```http
X-Api-Key: tibus_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

ou

```http
Authorization: Bearer tibus_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

La clé est liée à une **compagnie** et un **externalSystem** (ex. `default`, `erp-compagnie-x`).

**Base URL** :

```
https://<PROJECT_REF>.supabase.co/functions/v1/partner-itinerary-api
```

---

## Modèle de données Tibus

| Concept externe | Table Tibus | ID utilisé pour la vente |
|-----------------|-------------|----------------------------|
| Gare | `Gares` | UUID Tibus (ou mapping externe) |
| Itinéraire | `ProgrammationTrajets` | créé automatiquement |
| Départ | `Reservations` | `tibusReservationId` |
| Billet | `ReservationBus` | `bookingId` + `ticketReference` (TB-…) |

---

## Endpoints

### Santé

```http
GET /v1/health
```

Réponse : `{ "ok": true, "service": "partner-itinerary-api", "version": 2 }`

---

### Gares — mapping

Lie un identifiant de gare **externe** à une gare Tibus existante.

```http
POST /v1/gares/mappings
Content-Type: application/json
X-Api-Key: tibus_...

{
  "externalGareId": "GARE-LOME-CENTRAL",
  "tibusGareId": "550e8400-e29b-41d4-a716-446655440000",
  "externalName": "Gare Lomé Centre"
}
```

```http
GET /v1/gares/mappings
```

---

### Départs — synchronisation

Crée ou met à jour un départ. Idempotent sur `externalDepartureId`.

```http
PUT /v1/departures
Content-Type: application/json

{
  "externalDepartureId": "DEP-2026-06-15-0800",
  "departureAt": "2026-06-15T08:00:00.000Z",
  "capacity": 45,
  "price": 7500,
  "kilometrage": 320,
  "origin": { "externalGareId": "GARE-LOME-CENTRAL" },
  "destination": { "externalGareId": "GARE-KARA" },
  "payload": { "busPlate": "TG-1234-AB" }
}
```

Alternative avec UUID Tibus directs :

```json
{
  "externalDepartureId": "DEP-001",
  "departGareId": "<uuid>",
  "finalGareId": "<uuid>",
  "departureAt": "2026-06-15T08:00:00Z",
  "capacity": 45,
  "price": 7500
}
```

Réponse :

```json
{
  "externalDepartureId": "DEP-2026-06-15-0800",
  "tibusReservationId": "uuid-reservation",
  "tibusTrajetId": "uuid-trajet",
  "created": true,
  "availability": {
    "totalSeats": 45,
    "seatsBooked": 0,
    "seatsHeld": 0,
    "seatsAvailable": 45,
    "occupiedSeats": []
  }
}
```

**Webhook émis** : `departure.synced`

---

### Disponibilité

```http
GET /v1/departures/DEP-2026-06-15-0800/availability
```

```json
{
  "reservationId": "uuid",
  "externalDepartureId": "DEP-2026-06-15-0800",
  "totalSeats": 45,
  "seatsBooked": 12,
  "seatsHeld": 2,
  "seatsAvailable": 31,
  "occupiedSeats": ["1", "3", "7"],
  "departureAt": "2026-06-15T08:00:00.000Z",
  "price": 7500,
  "currency": "XOF",
  "origin": { "gareId": "...", "name": "Gare Lomé" },
  "destination": { "gareId": "...", "name": "Gare Kara" }
}
```

**Règle métier** : seuls les billets **émis** comptent (`isReservation = false` ou paiement avec `txID`). Les **holds** partenaire (`mode: hold`) réduisent aussi `seatsAvailable`.

---

### Liste des départs synchronisés

```http
GET /v1/departures?from=2026-06-01T00:00:00Z&to=2026-06-30T23:59:59Z&limit=100
```

---

## Réservations & ventes (extension)

### Vente immédiate (`mode: sale`)

Émet un billet confirmé tout de suite.

```http
POST /v1/bookings
Content-Type: application/json

{
  "externalDepartureId": "DEP-2026-06-15-0800",
  "externalBookingId": "BOOK-EXT-001",
  "passengerName": "Kofi Mensah",
  "passengerPhone": "90123456",
  "seatNumber": "12",
  "mode": "sale",
  "externalPaymentRef": "PAY-PARTNER-999",
  "price": 7500,
  "payload": { "source": "erp" }
}
```

Réponse `201` :

```json
{
  "partnerBookingId": "uuid",
  "externalBookingId": "BOOK-EXT-001",
  "bookingId": "uuid",
  "ticketReference": "TB-A1B2C3D4",
  "status": "confirmed",
  "availability": { "seatsAvailable": 30, ... }
}
```

**Webhook** : `booking.created`

---

### Réservation temporaire (`mode: hold`)

Bloque une place sans émettre le billet (défaut 15 min, min 5).

```http
POST /v1/bookings

{
  "externalDepartureId": "DEP-2026-06-15-0800",
  "externalBookingId": "HOLD-001",
  "passengerName": "Ama Diallo",
  "seatNumber": "8",
  "mode": "hold",
  "holdMinutes": 20
}
```

Réponse : `"status": "hold"`, `"holdExpiresAt": "..."`

**Webhook** : `booking.created`

---

### Confirmer un hold (après paiement externe)

```http
POST /v1/bookings/HOLD-001/confirm
Content-Type: application/json

{
  "externalPaymentRef": "PAY-PARTNER-1001"
}
```

**Webhook** : `booking.confirmed`

---

### Consulter une réservation

```http
GET /v1/bookings/BOOK-EXT-001
```

---

### Annuler

```http
DELETE /v1/bookings/BOOK-EXT-001
```

Impossible si billet déjà embarqué (`ticketStatus = on_board`).

**Webhook** : `booking.cancelled`

---

## Webhooks

### Configuration (console owner)

`/fr/owner/partner-api` → section **Webhooks de vente**

- URL HTTPS de réception
- Secret `whsec_…` (affiché une fois)
- Événements par défaut : `booking.created`, `booking.confirmed`, `booking.cancelled`
- `departure.synced` si endpoint abonné à cet event

### Format de livraison

```http
POST https://votre-erp.com/tibus/webhook
Content-Type: application/json
X-Tibus-Event: booking.created
X-Tibus-Signature: sha256=<hmac_hex>
X-Tibus-Delivery: <uuid>

{
  "id": "uuid-event",
  "type": "booking.created",
  "createdAt": "2026-06-10T12:00:00.000Z",
  "data": { ... }
}
```

### Vérification de signature (côté partenaire)

```javascript
import crypto from "crypto";

function verifyTibusWebhook(secret, rawBody, signatureHeader) {
  const expected = "sha256=" + crypto
    .createHmac("sha256", secret)
    .update(rawBody, "utf8")
    .digest("hex");
  return crypto.timingSafeEqual(
    Buffer.from(expected),
    Buffer.from(signatureHeader),
  );
}
```

### Événements

| Event | Quand |
|-------|-------|
| `departure.synced` | PUT `/v1/departures` réussi |
| `booking.created` | POST `/v1/bookings` (sale ou hold) |
| `booking.confirmed` | POST `.../confirm` |
| `booking.cancelled` | DELETE `/v1/bookings/...` |

Les livraisons sont journalisées dans `PartnerWebhookDeliveries` (visible dans la console owner).

---

## Flux d’intégration recommandé

```mermaid
sequenceDiagram
  participant ERP as Système externe
  participant API as partner-itinerary-api
  participant Tibus as Base Tibus

  ERP->>API: POST /v1/gares/mappings
  ERP->>API: PUT /v1/departures
  API->>Tibus: partner_upsert_departure
  API-->>ERP: tibusReservationId + availability

  Note over ERP: Voyageur réserve sur ERP
  ERP->>API: GET .../availability
  ERP->>API: POST /v1/bookings (hold)
  API-->>ERP: status hold
  ERP->>API: POST .../confirm
  API->>Tibus: billet émis partner_api
  API-->>ERP: ticketReference TB-...
  API->>ERP: webhook booking.confirmed
```

---

## Codes d’erreur courants

| Message | Cause |
|---------|-------|
| `Cle API invalide` | Clé absente, révoquée ou incorrecte |
| `Gare externe non mappee` | Mapping manquant — POST `/v1/gares/mappings` |
| `Depart externe introuvable` | `externalDepartureId` non synchronisé |
| `Plus de places disponibles` | Capacité atteinte (billets + holds) |
| `Siege deja vendu` | `seatNumber` déjà pris |
| `Reservation externe deja existante` | `externalBookingId` dupliqué |
| `Reservation expiree` | Hold dépassé — recréer ou annuler |

---

## Fichiers source (repo)

| Fichier | Rôle |
|---------|------|
| `082_partner_itinerary_api.sql` | Schéma + RPC sync |
| `083_partner_api_bookings_webhooks.sql` | Bookings + webhooks |
| `supabase/functions/partner-itinerary-api/index.ts` | Routes HTTP |
| `supabase/functions/_shared/partner-auth.ts` | Auth clé API |
| `supabase/functions/_shared/partner-webhooks.ts` | Envoi webhooks HMAC |
| `src/lib/supabase/partner-itinerary.ts` | Client owner |
| `src/pages/owner/PartnerApiPage.tsx` | UI clés + webhooks |

---

## Limites & évolutions

- Pas de remboursement automatique via API (annulation marque le billet `cancelled`).
- Canal `partner_api` : hors fond de garantie voyageur (`traveler` / `seller_reservation`).
- Paiement en ligne Tibus (`payment-initialize`) reste disponible sur le même `tibusReservationId` si le départ est visible dans la recherche publique.
- Évolutions possibles : webhooks retry automatique, OAuth2, catalogue multi-compagnies agrégateur.
