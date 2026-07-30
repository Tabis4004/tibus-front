-- Lot 195: relève les seuils de scaling (x3 sur vendeurs / réservations-jour /
-- connexions estimées) — les seuils d'origine (migration 118) étaient
-- beaucoup trop bas pour une activité normale (ex. alerte à 17 vendeurs
-- actifs alors que ça ne bloque rien techniquement). Ces seuils ne sont que
-- des recommandations d'infra pour le superadmin (onglet Métriques scaling),
-- ils n'ont jamais limité l'ajout de vendeurs ni les réservations.
--
-- On garde la structure et le ratio d'alerte à 80 % du palier (logique dans
-- sync_platform_scaling_notifications, migration 118, inchangée) — seuls les
-- paliers eux-mêmes sont relevés (x3), en gardant la cohérence : le plafond
-- d'un palier = le seuil de bascule vers le palier suivant.

CREATE OR REPLACE FUNCTION public._resolve_scaling_tier(
  p_sellers integer,
  p_avg_daily numeric,
  p_connections integer
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_sellers >= 2400 OR p_avg_daily >= 150000 OR p_connections >= 1800 THEN
    RETURN 'tres_haut_volume';
  ELSIF p_sellers >= 900 OR p_avg_daily >= 45000 OR p_connections >= 600 THEN
    RETURN 'national';
  ELSIF p_sellers >= 300 OR p_avg_daily >= 9000 OR p_connections >= 240 THEN
    RETURN 'fort_trafic';
  ELSIF p_sellers >= 90 OR p_avg_daily >= 1500 OR p_connections >= 90 THEN
    RETURN 'croissance';
  END IF;
  RETURN 'demarrage';
END;
$$;

CREATE OR REPLACE FUNCTION public._scaling_tier_thresholds(p_tier text)
RETURNS TABLE(sellers integer, avg_daily numeric, connections integer)
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  CASE p_tier
    WHEN 'croissance' THEN
      RETURN QUERY SELECT 300, 9000::numeric, 240;
    WHEN 'fort_trafic' THEN
      RETURN QUERY SELECT 900, 45000::numeric, 600;
    WHEN 'national' THEN
      RETURN QUERY SELECT 2400, 150000::numeric, 1800;
    WHEN 'tres_haut_volume' THEN
      RETURN QUERY SELECT 3000, 180000::numeric, 2400;
    ELSE
      RETURN QUERY SELECT 60, 1500::numeric, 90;
  END CASE;
END;
$$;
