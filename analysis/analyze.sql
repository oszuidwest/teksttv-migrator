-- Tekst TV migratie: productiedata-analyse
-- Draai uitsluitend tegen een afgeschermde lokale databasekopie, bijvoorbeeld:
-- docker exec -i <db-container> mariadb <database> < analysis/analyze.sql
-- Deel de uitvoer niet zonder aanvullende controle op credentials en interne identifiers.

SELECT '=== 1. Post meta: aantallen per key ===' AS section;
SELECT meta_key, COUNT(*) AS cnt
FROM wp_postmeta
WHERE meta_key IN (
  'post_in_kabelkrant', 'post_kabelkrant_content', 'post_kabelkrant_content_gpt',
  'post_kabelkrant_datum_uit', 'post_kabelkrant_dagen', 'post_kabelkrant_extra_afbeeldingen',
  'artikel_in_kabelkrant', 'artikel_kabelkrant_content', 'post_kabelkrant_datum_in'
)
GROUP BY meta_key ORDER BY cnt DESC;

SELECT '=== 2. Actieve kabelkrant-posts (gepubliceerd, in_kabelkrant=1) ===' AS section;
SELECT COUNT(*) AS published_in_kabelkrant
FROM wp_posts p
JOIN wp_postmeta m ON m.post_id = p.ID AND m.meta_key = 'post_in_kabelkrant' AND m.meta_value = '1'
WHERE p.post_type = 'post' AND p.post_status = 'publish';

SELECT '=== 2b. Idem met niet-lege content ===' AS section;
SELECT COUNT(*) AS with_content
FROM wp_posts p
JOIN wp_postmeta m ON m.post_id = p.ID AND m.meta_key = 'post_in_kabelkrant' AND m.meta_value = '1'
JOIN wp_postmeta c ON c.post_id = p.ID AND c.meta_key = 'post_kabelkrant_content' AND TRIM(c.meta_value) <> ''
WHERE p.post_type = 'post' AND p.post_status = 'publish';

SELECT '=== 2c. Recente actieve posts (laatste 60 dagen) ===' AS section;
SELECT COUNT(*) AS recent_active
FROM wp_posts p
JOIN wp_postmeta m ON m.post_id = p.ID AND m.meta_key = 'post_in_kabelkrant' AND m.meta_value = '1'
JOIN wp_postmeta c ON c.post_id = p.ID AND c.meta_key = 'post_kabelkrant_content' AND TRIM(c.meta_value) <> ''
WHERE p.post_type = 'post' AND p.post_status = 'publish'
  AND p.post_date >= DATE_SUB(NOW(), INTERVAL 60 DAY);

SELECT '=== 3. Datumformaat post_kabelkrant_datum_uit (verwacht: Ymd) ===' AS section;
SELECT
  SUM(meta_value REGEXP '^[0-9]{8}$') AS fmt_Ymd,
  SUM(meta_value REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') AS fmt_Y_m_d,
  SUM(TRIM(meta_value) = '') AS empty_val,
  SUM(meta_value NOT REGEXP '^[0-9]{8}$' AND meta_value NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' AND TRIM(meta_value) <> '') AS other_fmt,
  COUNT(*) AS total
FROM wp_postmeta WHERE meta_key = 'post_kabelkrant_datum_uit';

SELECT '=== 3b. Voorbeelden afwijkende datumwaardes ===' AS section;
SELECT post_id, meta_value FROM wp_postmeta
WHERE meta_key = 'post_kabelkrant_datum_uit'
  AND meta_value NOT REGEXP '^[0-9]{8}$' AND TRIM(meta_value) <> ''
LIMIT 10;

SELECT '=== 4. Dagen-veld: verdeling (alle 7 / subset / leeg) ===' AS section;
SELECT
  SUM(meta_value = 'a:7:{i:0;s:1:"1";i:1;s:1:"2";i:2;s:1:"3";i:3;s:1:"4";i:4;s:1:"5";i:5;s:1:"6";i:6;s:1:"7";}') AS all7_standard,
  SUM(meta_value LIKE 'a:7:%') AS all7_any,
  SUM(meta_value = 'a:0:{}') AS empty_array,
  SUM(TRIM(meta_value) = '') AS empty_string,
  SUM(meta_value LIKE 'a:%' AND meta_value NOT LIKE 'a:7:%' AND meta_value <> 'a:0:{}') AS subset,
  COUNT(*) AS total
FROM wp_postmeta WHERE meta_key = 'post_kabelkrant_dagen';

SELECT '=== 4b. Voorbeelden subset-dagen ===' AS section;
SELECT post_id, meta_value FROM wp_postmeta
WHERE meta_key = 'post_kabelkrant_dagen'
  AND meta_value LIKE 'a:%' AND meta_value NOT LIKE 'a:7:%' AND meta_value <> 'a:0:{}'
LIMIT 10;

SELECT '=== 5. Extra afbeeldingen: hoeveel posts, voorbeeldwaardes ===' AS section;
SELECT COUNT(*) AS cnt, SUM(TRIM(meta_value) <> '' AND meta_value <> 'a:0:{}') AS non_empty
FROM wp_postmeta WHERE meta_key = 'post_kabelkrant_extra_afbeeldingen';
SELECT post_id, LEFT(meta_value, 120) AS sample FROM wp_postmeta
WHERE meta_key = 'post_kabelkrant_extra_afbeeldingen' AND meta_value LIKE 'a:%' AND meta_value <> 'a:0:{}'
LIMIT 5;

SELECT '=== 6. GPT-veld vs content: audit-verdeling (ruwe telling) ===' AS section;
SELECT
  SUM(TRIM(IFNULL(g.meta_value,'')) = '') AS fully_human,
  SUM(TRIM(IFNULL(g.meta_value,'')) <> '' AND TRIM(g.meta_value) = TRIM(c.meta_value)) AS ai_unedited,
  SUM(TRIM(IFNULL(g.meta_value,'')) <> '' AND TRIM(g.meta_value) <> TRIM(c.meta_value)) AS ai_edited,
  COUNT(*) AS total
FROM wp_postmeta c
LEFT JOIN wp_postmeta g ON g.post_id = c.post_id AND g.meta_key = 'post_kabelkrant_content_gpt'
WHERE c.meta_key = 'post_kabelkrant_content' AND TRIM(c.meta_value) <> '';

SELECT '=== 7. Content: paginascheiding en regioprefix ===' AS section;
SELECT
  SUM(meta_value LIKE '%---%') AS with_separator,
  SUM(meta_value REGEXP '^[[:upper:]]{2,}') AS starts_uppercase_prefix,
  SUM(meta_value LIKE '%<%') AS contains_html,
  COUNT(*) AS total
FROM wp_postmeta WHERE meta_key = 'post_kabelkrant_content' AND TRIM(meta_value) <> '';

SELECT '=== 8. Options: alle teksttv-gerelateerde rijen ===' AS section;
SELECT option_name, LENGTH(option_value) AS len
FROM wp_options
WHERE option_name LIKE 'teksttv%' OR option_name LIKE '_teksttv%'
   OR option_name LIKE 'options_teksttv%' OR option_name LIKE '_options_teksttv%'
   OR option_name LIKE '%openweather%'
ORDER BY option_name;

SELECT '=== 9. zw-ttvgpt opties (incl legacy; gevoelige waarden gemaskeerd) ===' AS section;
SELECT
  option_name,
  CASE
    WHEN option_name = 'ttvgpt_word_limit' THEN option_value
    WHEN TRIM(option_value) = '' THEN '[empty]'
    ELSE CONCAT('[redacted; ', CHAR_LENGTH(option_value), ' characters]')
  END AS safe_value
FROM wp_options
WHERE option_name IN ('zw_ttvgpt_settings', 'ttvgpt_api_key', 'ttvgpt_word_limit', 'ttvgpt_model');

SELECT '=== 10. Blokken per kanaal (layout-volgorde) ===' AS section;
SELECT option_name, option_value FROM wp_options
WHERE option_name IN ('teksttv_tv1_teksttv_blokken', 'teksttv_tv2_teksttv_blokken',
                      'teksttv_tv1_teksttv_ticker', 'teksttv_tv2_teksttv_ticker',
                      'teksttv_tv1_teksttv_reclame', 'teksttv_tv2_teksttv_reclame');

SELECT '=== 11. Alle blok-subvelden tv1/tv2 (voor mapping) ===' AS section;
SELECT option_name, LEFT(option_value, 200) AS val
FROM wp_options
WHERE (option_name LIKE 'teksttv_tv1_teksttv_blokken_%' OR option_name LIKE 'teksttv_tv2_teksttv_blokken_%'
    OR option_name LIKE 'teksttv_tv1_teksttv_ticker_%' OR option_name LIKE 'teksttv_tv2_teksttv_ticker_%')
  AND option_name NOT LIKE '\_%'
ORDER BY option_name;

SELECT '=== 12. Campagnes: subvelden (groepen, datums, slides) ===' AS section;
SELECT option_name, LEFT(option_value, 300) AS val
FROM wp_options
WHERE (option_name LIKE 'teksttv_tv1_teksttv_reclame_%' OR option_name LIKE 'teksttv_tv2_teksttv_reclame_%')
  AND option_name NOT LIKE '\_%'
ORDER BY option_name;

SELECT '=== 13. Multi-group campagnes (campagne_groep met >1 element) ===' AS section;
SELECT option_name, option_value FROM wp_options
WHERE option_name REGEXP 'teksttv_tv[0-9]_teksttv_reclame_[0-9]+_campagne_groep'
  AND option_value NOT LIKE 'a:1:%';

SELECT '=== 14. Term meta: categorie-afbeeldingen ===' AS section;
SELECT tm.term_id, t.name, tm.meta_value AS attachment_id
FROM wp_termmeta tm
JOIN wp_terms t ON t.term_id = tm.term_id
WHERE tm.meta_key = 'teksttv_categorie_afbeelding';

SELECT '=== 15. Legacy options (single-channel tijdperk) ===' AS section;
SELECT option_name, LENGTH(option_value) AS len FROM wp_options
WHERE option_name LIKE 'options\_teksttv%' ORDER BY option_name;

SELECT '=== 16. Yoast primary category aanwezig? ===' AS section;
SELECT COUNT(*) AS posts_with_primary_cat FROM wp_postmeta WHERE meta_key = '_yoast_wpseo_primary_category';

SELECT '=== 17. Nieuwe plugin al aanwezig? (_teksttv_* meta / teksttv_ opties) ===' AS section;
SELECT meta_key, COUNT(*) AS cnt FROM wp_postmeta WHERE meta_key LIKE '\_teksttv\_%' GROUP BY meta_key;
SELECT option_name FROM wp_options WHERE option_name IN
  ('teksttv_channels','teksttv_features','teksttv_loop_tv1','teksttv_loop_tv2',
   'teksttv_ticker_tv1','teksttv_ticker_tv2','teksttv_campaigns','teksttv_campaign_groups',
   'teksttv_ai_prompts','teksttv_openweather_api_key');

SELECT '=== 18. Regio-taxonomie: termen ===' AS section;
SELECT t.term_id, t.name, t.slug, tt.count
FROM wp_term_taxonomy tt JOIN wp_terms t ON t.term_id = tt.term_id
WHERE tt.taxonomy = 'regio' ORDER BY tt.count DESC;

SELECT '=== 19. Actieve plugins ===' AS section;
SELECT option_value FROM wp_options WHERE option_name = 'active_plugins';

SELECT '=== 20. Datum-uit in verleden vs toekomst (actieve posts) ===' AS section;
SELECT
  SUM(d.meta_value <> '' AND STR_TO_DATE(d.meta_value, '%Y%m%d') < CURDATE()) AS expired,
  SUM(d.meta_value <> '' AND STR_TO_DATE(d.meta_value, '%Y%m%d') >= CURDATE()) AS future,
  SUM(TRIM(IFNULL(d.meta_value,'')) = '') AS no_end_date
FROM wp_posts p
JOIN wp_postmeta m ON m.post_id = p.ID AND m.meta_key = 'post_in_kabelkrant' AND m.meta_value = '1'
LEFT JOIN wp_postmeta d ON d.post_id = p.ID AND d.meta_key = 'post_kabelkrant_datum_uit'
WHERE p.post_type = 'post' AND p.post_status = 'publish';
