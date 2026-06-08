-- Lot 57: seed frais GeniusPay — tous les pays couverts (remplace le lot 56 CI-only)
-- Source tarifs: https://geniuspay.ci/pricing (juin 2026)
-- PRÉREQUIS: 019, 022, 024, 025, 055_geniuspay_gateway.sql
--
-- Correctifs lot 57b:
--   - round(..., 2) casté en numeric (PostgreSQL n'a pas round(float8, int))
--   - upsert inline (UPDATE active / réactive inactive / INSERT)
--   - résolution pays tolérante (accents / variantes)

-- ---------------------------------------------------------------------------
-- 0. Prérequis
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'GatewayPaymentFees'
      AND column_name = 'network'
  ) THEN
    RAISE EXCEPTION 'Colonne GatewayPaymentFees.network absente — exécutez 022_gateway_payment_network.sql';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 1. Pays GeniusPay absents de la table Countries
-- ---------------------------------------------------------------------------
INSERT INTO "Countries" ("name", "currency")
SELECT v.name, v.currency
FROM (VALUES
  ('Sénégal', 'XOF'),
  ('Mali', 'XOF'),
  ('Burkina Faso', 'XOF'),
  ('Kenya', 'KES'),
  ('Rwanda', 'RWF'),
  ('Ghana', 'GHS'),
  ('Nigeria', 'NGN'),
  ('RD Congo', 'CDF'),
  ('République du Congo', 'XAF'),
  ('Ouganda', 'UGX'),
  ('Sierra Leone', 'SLE'),
  ('Guinée', 'GNF'),
  ('Niger', 'XOF'),
  ('Guinée-Bissau', 'XOF'),
  ('Zambie', 'ZMW'),
  ('Tanzanie', 'TZS'),
  ('Malawi', 'MWK'),
  ('Mozambique', 'MZN')
) AS v(name, currency)
WHERE NOT EXISTS (
  SELECT 1 FROM "Countries" c WHERE lower(trim(c.name)) = lower(trim(v.name))
);

-- ---------------------------------------------------------------------------
-- 2. Seed par pays / réseau
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  rec record;
  v_country_id uuid;
  v_existing_id uuid;
  v_method text;
  v_network text;
  v_key text;
BEGIN
  FOR rec IN
    SELECT *
    FROM (VALUES
      ('Côte d''Ivoire', 'mobile_money', 'wave', 1.5::float8, 1.0::float8, 100::float8),
      ('Côte d''Ivoire', 'mobile_money', 'orange', 3.5, 1.0, 100),
      ('Côte d''Ivoire', 'mobile_money', 'mtn', 3.5, 1.0, 100),
      ('Côte d''Ivoire', 'mobile_money', 'moov', 3.5, 1.0, 100),
      ('Côte d''Ivoire', 'mobile_money', 'default', 3.5, 1.0, 100),
      ('Côte d''Ivoire', 'card', 'default', 5.0, 1.0, 100),

      ('Sénégal', 'mobile_money', 'orange', 3.5, 1.0, 100),
      ('Sénégal', 'mobile_money', 'wave', 3.5, 1.0, 100),
      ('Sénégal', 'mobile_money', 'free', 3.5, 1.0, 100),
      ('Sénégal', 'mobile_money', 'default', 3.5, 1.0, 100),

      ('Bénin', 'mobile_money', 'mtn', 3.5, 1.0, 100),
      ('Bénin', 'mobile_money', 'moov', 3.5, 1.0, 100),
      ('Bénin', 'mobile_money', 'default', 3.5, 1.0, 100),

      ('Cameroun', 'mobile_money', 'mtn', 3.5, 1.0, 100),
      ('Cameroun', 'mobile_money', 'orange', 3.5, 1.0, 100),
      ('Cameroun', 'mobile_money', 'default', 3.5, 1.0, 100),
      ('Cameroun', 'card', 'default', 5.0, 1.0, 100),

      ('Togo', 'mobile_money', 'moov', 3.5, 1.0, 100),
      ('Togo', 'mobile_money', 'togocel', 3.5, 1.0, 100),
      ('Togo', 'mobile_money', 'default', 3.5, 1.0, 100),

      ('Mali', 'mobile_money', 'orange', 3.5, 1.0, 100),
      ('Mali', 'mobile_money', 'mobicash', 3.5, 1.0, 100),
      ('Mali', 'mobile_money', 'default', 3.5, 1.0, 100),
      ('Mali', 'card', 'default', 5.0, 1.0, 100),

      ('Burkina Faso', 'mobile_money', 'orange', 3.5, 1.0, 100),
      ('Burkina Faso', 'mobile_money', 'wave', 3.5, 1.0, 100),
      ('Burkina Faso', 'mobile_money', 'moov', 3.5, 1.0, 100),
      ('Burkina Faso', 'mobile_money', 'mobicash', 3.5, 1.0, 100),
      ('Burkina Faso', 'mobile_money', 'default', 3.5, 1.0, 100),

      ('Kenya', 'mobile_money', 'mpesa', 3.5, 1.0, 100),
      ('Kenya', 'mobile_money', 'default', 3.5, 1.0, 100),

      ('Rwanda', 'mobile_money', 'airtel', 3.5, 1.0, 100),
      ('Rwanda', 'mobile_money', 'mtn', 3.5, 1.0, 100),
      ('Rwanda', 'mobile_money', 'default', 3.5, 1.0, 100),

      ('Ghana', 'mobile_money', 'mtn', 3.5, 1.0, 100),
      ('Ghana', 'mobile_money', 'default', 3.5, 1.0, 100),
      ('Ghana', 'card', 'default', 5.0, 1.0, 100),

      ('Nigeria', 'mobile_money', 'default', 3.5, 1.0, 100),
      ('Nigeria', 'card', 'default', 5.0, 1.0, 100),

      ('RD Congo', 'mobile_money', 'airtel', 3.5, 1.0, 100),
      ('RD Congo', 'mobile_money', 'orange', 3.5, 1.0, 100),
      ('RD Congo', 'mobile_money', 'vodacom', 3.5, 1.0, 100),
      ('RD Congo', 'mobile_money', 'default', 3.5, 1.0, 100),

      ('République du Congo', 'mobile_money', 'airtel', 3.5, 1.0, 100),
      ('République du Congo', 'mobile_money', 'mtn', 3.5, 1.0, 100),
      ('République du Congo', 'mobile_money', 'orange', 3.5, 1.0, 100),
      ('République du Congo', 'mobile_money', 'mpesa', 3.5, 1.0, 100),
      ('République du Congo', 'mobile_money', 'default', 3.5, 1.0, 100),

      ('Gabon', 'mobile_money', 'airtel', 3.5, 1.0, 100),
      ('Gabon', 'mobile_money', 'default', 3.5, 1.0, 100),

      ('Ouganda', 'mobile_money', 'airtel', 3.5, 1.0, 100),
      ('Ouganda', 'mobile_money', 'mtn', 3.5, 1.0, 100),
      ('Ouganda', 'mobile_money', 'default', 3.5, 1.0, 100),

      ('Sierra Leone', 'mobile_money', 'orange', 3.5, 1.0, 100),
      ('Sierra Leone', 'mobile_money', 'default', 3.5, 1.0, 100),

      ('Guinée', 'mobile_money', 'orange', 5.0, 1.0, 100),
      ('Guinée', 'mobile_money', 'default', 5.0, 1.0, 100),
      ('Guinée', 'card', 'default', 5.0, 1.0, 100),

      ('Niger', 'mobile_money', 'airtel', 5.0, 1.0, 100),
      ('Niger', 'mobile_money', 'default', 5.0, 1.0, 100),

      ('Guinée-Bissau', 'mobile_money', 'orange', 5.0, 1.0, 100),
      ('Guinée-Bissau', 'mobile_money', 'default', 5.0, 1.0, 100),

      ('Zambie', 'mobile_money', 'mtn', 3.5, 1.0, 100),
      ('Zambie', 'mobile_money', 'zamtel', 3.5, 1.0, 100),
      ('Zambie', 'mobile_money', 'default', 3.5, 1.0, 100),

      ('Tanzanie', 'mobile_money', 'mpesa', 3.5, 1.0, 100),
      ('Tanzanie', 'mobile_money', 'airtel', 3.5, 1.0, 100),
      ('Tanzanie', 'mobile_money', 'tigo', 3.5, 1.0, 100),
      ('Tanzanie', 'mobile_money', 'default', 3.5, 1.0, 100),

      ('Malawi', 'mobile_money', 'airtel', 3.5, 1.0, 100),
      ('Malawi', 'mobile_money', 'default', 3.5, 1.0, 100),

      ('Mozambique', 'mobile_money', 'mpesa', 3.5, 1.0, 100),
      ('Mozambique', 'mobile_money', 'vodacom', 3.5, 1.0, 100),
      ('Mozambique', 'mobile_money', 'default', 3.5, 1.0, 100)
    ) AS seed(country_name, method, network, y_pct, z_pct, f_fixed)
  LOOP
    v_key := lower(trim(rec.country_name));
    v_country_id := NULL;

    SELECT c.id
    INTO v_country_id
    FROM "Countries" c
    WHERE lower(trim(c.name)) = v_key
    LIMIT 1;

    IF v_country_id IS NULL AND v_key LIKE '%ivoire%' THEN
      SELECT c.id INTO v_country_id FROM "Countries" c
      WHERE lower(c.name) LIKE '%ivoire%' ORDER BY c.name LIMIT 1;
    END IF;

    IF v_country_id IS NULL AND (v_key LIKE '%benin%' OR v_key LIKE '%bénin%') THEN
      SELECT c.id INTO v_country_id FROM "Countries" c
      WHERE lower(c.name) LIKE '%benin%' OR lower(c.name) LIKE '%bénin%'
      ORDER BY c.name LIMIT 1;
    END IF;

    IF v_country_id IS NULL AND v_key LIKE '%république du congo%' THEN
      SELECT c.id INTO v_country_id FROM "Countries" c
      WHERE lower(c.name) LIKE '%république du congo%'
         OR lower(c.name) LIKE '%republique du congo%'
      ORDER BY c.name LIMIT 1;
    END IF;

    IF v_country_id IS NULL AND v_key LIKE '%rd congo%' THEN
      SELECT c.id INTO v_country_id FROM "Countries" c
      WHERE lower(c.name) LIKE 'rd congo%'
         OR lower(c.name) LIKE '%démocratique%congo%'
         OR lower(c.name) LIKE '%democratique%congo%'
      ORDER BY c.name LIMIT 1;
    END IF;

    IF v_country_id IS NULL THEN
      RAISE WARNING 'Pays introuvable pour seed GeniusPay: %', rec.country_name;
      CONTINUE;
    END IF;

    v_method := lower(trim(rec.method));
    v_network := lower(trim(COALESCE(rec.network, 'default')));
    v_existing_id := NULL;

    SELECT gpf.id
    INTO v_existing_id
    FROM "GatewayPaymentFees" gpf
    WHERE lower(gpf.gateway) = 'geniuspay'
      AND gpf."countryId" = v_country_id
      AND lower(gpf.method) = v_method
      AND lower(gpf.network) = v_network
      AND gpf."isActive" = true
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      UPDATE "GatewayPaymentFees"
      SET
        "yPercent" = rec.y_pct,
        "zPercent" = rec.z_pct,
        "fFixed" = rec.f_fixed,
        "isActive" = true,
        "updatedAt" = now()
      WHERE id = v_existing_id;
      CONTINUE;
    END IF;

    SELECT gpf.id
    INTO v_existing_id
    FROM "GatewayPaymentFees" gpf
    WHERE lower(gpf.gateway) = 'geniuspay'
      AND gpf."countryId" = v_country_id
      AND lower(gpf.method) = v_method
      AND lower(gpf.network) = v_network
      AND gpf."isActive" = false
    ORDER BY gpf."updatedAt" DESC
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      UPDATE "GatewayPaymentFees"
      SET
        "yPercent" = rec.y_pct,
        "zPercent" = rec.z_pct,
        "fFixed" = rec.f_fixed,
        "isActive" = true,
        "updatedAt" = now()
      WHERE id = v_existing_id;
      CONTINUE;
    END IF;

    INSERT INTO "GatewayPaymentFees" (
      gateway, "countryId", method, network,
      "yPercent", "zPercent", "fFixed", "isActive", "updatedAt"
    ) VALUES (
      'geniuspay', v_country_id, v_method, v_network,
      rec.y_pct, rec.z_pct, rec.f_fixed, true, now()
    );
  END LOOP;

  RAISE NOTICE 'GeniusPay seed lot 57 terminé.';
END $$;

DROP FUNCTION IF EXISTS public._seed_geniuspay_fee(text, text, text, double precision, double precision, double precision);

-- ---------------------------------------------------------------------------
-- 3. Contrôle (round cast numeric — compatible PostgreSQL / Supabase)
-- ---------------------------------------------------------------------------
SELECT
  co.name AS country,
  co.currency,
  count(*) FILTER (WHERE gpf.method = 'mobile_money') AS mobile_rows,
  count(*) FILTER (WHERE gpf.method = 'card') AS card_rows,
  round((min(gpf."yPercent" + gpf."zPercent") FILTER (WHERE gpf.method = 'mobile_money'))::numeric, 2) AS min_mobile_pct,
  round((max(gpf."yPercent" + gpf."zPercent") FILTER (WHERE gpf.method = 'mobile_money'))::numeric, 2) AS max_mobile_pct
FROM "GatewayPaymentFees" gpf
JOIN "Countries" co ON co.id = gpf."countryId"
WHERE lower(gpf.gateway) = 'geniuspay'
  AND gpf."isActive" = true
GROUP BY co.name, co.currency
ORDER BY co.name;

SELECT
  gpf.gateway,
  co.name AS country,
  gpf.method,
  gpf.network,
  gpf."yPercent" AS y_operator_pct,
  gpf."zPercent" AS z_geniuspay_pct,
  gpf."fFixed" AS f_fixed,
  round((gpf."yPercent" + gpf."zPercent")::numeric, 2) AS total_pct
FROM "GatewayPaymentFees" gpf
JOIN "Countries" co ON co.id = gpf."countryId"
WHERE lower(gpf.gateway) = 'geniuspay'
  AND gpf."isActive" = true
ORDER BY co.name, gpf.method, gpf.network;
