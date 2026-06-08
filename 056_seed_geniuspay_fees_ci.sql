-- Lot 56: seed frais GeniusPay — Côte d'Ivoire (orange / mtn / moov / wave)
-- OBSOLÈTE: utiliser 057_seed_geniuspay_fees_all_countries.sql (le ON CONFLICT partiel du 056 échoue sur Supabase).
-- Source tarifs: https://geniuspay.ci/pricing (juin 2026)
-- PRÉREQUIS: 019_gateway_payment_fees.sql, 022_gateway_payment_network.sql, 024_gateway_fees_nullable.sql, 025_fedapay_fee_on_top.sql
--
-- Modèle Tibus (GatewayPaymentFees):
--   Y = frais opérateur / agrégateur (%)
--   Z = commission GeniusPay (1%)
--   F = fixe GeniusPay (100 XOF)
--
-- Grille GeniusPay CI:
--   Wave direct     → 1.5% + 1% + 100 XOF  = 2.5% + 100
--   Orange/MTN/Moov → 3.5% + 1% + 100 XOF  = 4.5% + 100  (PawaPay / PAL / Paystack)
--
-- Formule voyageur (gateway <> fedapay, lot 25): T = (V + F) / (1 - (Y+Z)/100)

DO $$
DECLARE
  v_country_id uuid;
  v_country_name text;
BEGIN
  SELECT co.id, co.name
  INTO v_country_id, v_country_name
  FROM "Countries" co
  WHERE lower(co.name) LIKE '%ivoire%'
     OR lower(co.name) LIKE '%cote d%'
     OR lower(co.name) LIKE '%côte d%'
  ORDER BY co.name
  LIMIT 1;

  IF v_country_id IS NULL THEN
    RAISE EXCEPTION 'Pays Côte d''Ivoire introuvable — exécutez 003_seed_countries.sql';
  END IF;

  -- Désactive d''anciennes lignes geniuspay CI mobile_money (réseau default) si présentes
  UPDATE "GatewayPaymentFees"
  SET "isActive" = false, "updatedAt" = now()
  WHERE lower(gateway) = 'geniuspay'
    AND "countryId" = v_country_id
    AND lower(method) = 'mobile_money'
    AND lower(network) = 'default'
    AND "isActive" = true;

  -- Wave — gateway Wave direct (meilleur tarif CI)
  INSERT INTO "GatewayPaymentFees" (
    gateway, "countryId", method, network,
    "yPercent", "zPercent", "fFixed", "isActive", "updatedAt"
  ) VALUES (
    'geniuspay', v_country_id, 'mobile_money', 'wave',
    1.5, 1.0, 100, true, now()
  )
  ON CONFLICT (gateway, "countryId", method, network)
  WHERE "isActive" = true
  DO UPDATE SET
    "yPercent" = EXCLUDED."yPercent",
    "zPercent" = EXCLUDED."zPercent",
    "fFixed" = EXCLUDED."fFixed",
    "isActive" = true,
    "updatedAt" = now();

  -- Orange Money — PawaPay / PAL / Paystack (~3.5% opérateur)
  INSERT INTO "GatewayPaymentFees" (
    gateway, "countryId", method, network,
    "yPercent", "zPercent", "fFixed", "isActive", "updatedAt"
  ) VALUES (
    'geniuspay', v_country_id, 'mobile_money', 'orange',
    3.5, 1.0, 100, true, now()
  )
  ON CONFLICT (gateway, "countryId", method, network)
  WHERE "isActive" = true
  DO UPDATE SET
    "yPercent" = EXCLUDED."yPercent",
    "zPercent" = EXCLUDED."zPercent",
    "fFixed" = EXCLUDED."fFixed",
    "isActive" = true,
    "updatedAt" = now();

  -- MTN MoMo
  INSERT INTO "GatewayPaymentFees" (
    gateway, "countryId", method, network,
    "yPercent", "zPercent", "fFixed", "isActive", "updatedAt"
  ) VALUES (
    'geniuspay', v_country_id, 'mobile_money', 'mtn',
    3.5, 1.0, 100, true, now()
  )
  ON CONFLICT (gateway, "countryId", method, network)
  WHERE "isActive" = true
  DO UPDATE SET
    "yPercent" = EXCLUDED."yPercent",
    "zPercent" = EXCLUDED."zPercent",
    "fFixed" = EXCLUDED."fFixed",
    "isActive" = true,
    "updatedAt" = now();

  -- Moov Money
  INSERT INTO "GatewayPaymentFees" (
    gateway, "countryId", method, network,
    "yPercent", "zPercent", "fFixed", "isActive", "updatedAt"
  ) VALUES (
    'geniuspay', v_country_id, 'mobile_money', 'moov',
    3.5, 1.0, 100, true, now()
  )
  ON CONFLICT (gateway, "countryId", method, network)
  WHERE "isActive" = true
  DO UPDATE SET
    "yPercent" = EXCLUDED."yPercent",
    "zPercent" = EXCLUDED."zPercent",
    "fFixed" = EXCLUDED."fFixed",
    "isActive" = true,
    "updatedAt" = now();

  -- Carte bancaire (optionnel — checkout GeniusPay card / Paystack)
  INSERT INTO "GatewayPaymentFees" (
    gateway, "countryId", method, network,
    "yPercent", "zPercent", "fFixed", "isActive", "updatedAt"
  ) VALUES (
    'geniuspay', v_country_id, 'card', 'default',
    5.0, 1.0, 100, true, now()
  )
  ON CONFLICT (gateway, "countryId", method, network)
  WHERE "isActive" = true
  DO UPDATE SET
    "yPercent" = EXCLUDED."yPercent",
    "zPercent" = EXCLUDED."zPercent",
    "fFixed" = EXCLUDED."fFixed",
    "isActive" = true,
    "updatedAt" = now();

  RAISE NOTICE 'GeniusPay CI seed OK — pays=% (%)', v_country_name, v_country_id;
END $$;

-- Contrôle rapide
SELECT
  gpf.gateway,
  co.name AS country,
  gpf.method,
  gpf.network,
  gpf."yPercent" AS y_operator_pct,
  gpf."zPercent" AS z_geniuspay_pct,
  gpf."fFixed" AS f_fixed_xof,
  round(gpf."yPercent" + gpf."zPercent", 2) AS total_pct,
  gpf."isActive"
FROM "GatewayPaymentFees" gpf
JOIN "Countries" co ON co.id = gpf."countryId"
WHERE lower(gpf.gateway) = 'geniuspay'
  AND lower(co.name) LIKE '%ivoire%'
ORDER BY gpf.method, gpf.network;

-- Exemple calcul (M=5000 XOF, X=0, compagnie démo CI) — remplacez l''UUID compagnie si besoin
-- SELECT public.calculate_traveler_payment_total(
--   5000,
--   (SELECT id FROM "Companies" WHERE name ILIKE '%démo%' OR name ILIKE '%demo%' LIMIT 1),
--   'geniuspay',
--   'mobile_money',
--   'wave'
-- );
