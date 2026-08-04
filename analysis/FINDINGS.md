# Productiedata-analyse (dump 2026-08-04)

Bron: afgeschermde lokale productiedump van 2026-08-04 (MariaDB 10.6), geïmporteerd in een
geïsoleerde lokale databaseomgeving. Bestandsnaam, database-identifiers en lokale credentials zijn
bewust niet vastgelegd. Queries: `analysis/analyze.sql`.

## Post meta (post type `post`)

| Key | Rijen | Bevinding |
|---|---|---|
| `post_in_kabelkrant` | 71.436 | 18.125 gepubliceerde posts met waarde '1' en niet-lege content; 458 daarvan uit de laatste 60 dagen |
| `post_kabelkrant_content` | 69.194 | 50.947 niet-leeg. Puur platte tekst (0x HTML), 97% begint met regioprefix ("ZUNDERT - "). 0x `---` paginascheiding. 964 rijen met newlines, maar slechts 24 kandidaat-posts met echte interne alinea's (rest is trailing Enter); nieuwste is van sept 2025. Gemiddeld 452 tekens, max 4.198 |
| `post_kabelkrant_content_gpt` | 46.268 | 4.548 binnen de migratie-kandidaten niet-leeg (audit-baseline) |
| `post_kabelkrant_datum_uit` | 47.162 | **100% leeg. Einddatum wordt in de praktijk nooit gebruikt.** |
| `post_kabelkrant_dagen` | 47.162 | **100% de standaard alle-7-dagen waarde. Dagbeperking wordt nooit gebruikt.** |
| `post_kabelkrant_extra_afbeeldingen` | 47.162 | **100% leeg. Extra afbeeldingen worden nooit gebruikt.** |
| `post_kabelkrant_datum_in` (legacy) | 35.303 | 100% leeg. Alleen opruimen |
| `artikel_in_kabelkrant` / `artikel_kabelkrant_content` (legacy) | 0 | Niet aanwezig |

Term meta `teksttv_categorie_afbeelding`: **0 rijen** - categorie-afbeeldingen onbenut. Sidebar-afbeelding komt in de praktijk dus altijd van de featured image (Yoast primary category is wel gezet op 23.284 posts, maar zonder categorie-afbeeldingen doet die er niet toe).

## Opties (kanalen tv1/tv2)

Loop tv1: `[blok_weer, blok_artikelen, blok_reclame]`
- weer: titel "Weerstation Woensdrecht", plaats "Woensdrecht"
- artikelen: aantal 15, geen categoriefilter, Regiofilter 9 term-IDs (2,3,29,498,456,5,539,717,557)
- reclame: groep 1, afbeelding_in 156952, geen afbeelding_uit

Loop tv2: `[blok_weer, blok_reclame, blok_artikelen, blok_reclame, blok_artikelen]`
- weer: "Weerstation Zundert" / "Zundert"
- reclame #1: groep 2, afbeelding_in 156918; reclame #3: groep 1, afbeelding_in 156918
- artikelen (2x identiek): aantal 6, Regiofilter 9 term-IDs (551,557,506,525,717,499,458,503,5)

Ticker beide kanalen: `[ticker_nufm, ticker_vandaagtv, ticker_straksfm]`
- `ticker_morgentv` en `ticker_tekst` worden niet gebruikt.

`blok_afbeelding` komt in geen enkel kanaal voor.

## Campagnes

tv1: 13 campagnes, tv2: 6. **Allemaal exact 1 groep** (alleen groepen "1" en "2" in gebruik) - het multi-group probleem bestaat niet in de praktijk. **Alle campagnes zijn verlopen** (laatste datum_uit = 20260416, vandaag 2026-08-04). Datums in raw `Ymd` formaat, zoals verwacht. Alle 20 gerefereerde attachment-IDs bestaan nog.

**Besluit eigenaar (2026-08-04): campagnes en campagnegroepen worden helemaal niet gemigreerd.** Nieuwe campagnes worden direct in de nieuwe plugin-UI aangemaakt; de `blok_reclame` posities in de loop worden dan pas ingericht (als `campaign` blokken met verse groepen) of weggelaten tot er weer campagnes zijn.

## zw-ttvgpt

- `zw_ttvgpt_settings` aanwezig: fine-tuned GPT-4.1-mini-model, word_limit 100, debug_mode true en een eigen system prompt (afwijkend van default). De exacte modelidentifier is bewust niet vastgelegd.
- Legacy opties `ttvgpt_api_key`, `ttvgpt_model` (fine-tuned GPT-3.5-model) en `ttvgpt_word_limit` (110) staan er nog - opruimen.
- **Gevoelige productiedata:** de dump bevat huidige en legacy OpenAI-credentials in plaintext. Nooit committen of delen; credentials na de migratie roteren.

## Omgeving

- Actieve plugins bevatten al `ai-provider-for-anthropic` en `ai-provider-for-openai` (WordPress AI Client providers) - de infra voor de nieuwe plugin-AI staat er al.
- Classic Editor actief. ACF Pro actief. Nieuwe teksttv-plugin nog niet aanwezig (geen `_teksttv_*` meta, geen `teksttv_*` opties nieuw-stijl).
- OpenWeather key aanwezig in `teksttv_instellingen_openweather_api_key` (32 tekens).
- Geen `options_teksttv_*` legacy rijen (single-channel tijdperk al opgeruimd).

## Gevolgen voor de migratie

Te migreren per post (alle 18.131 kandidaten):
1. `_teksttv_active` = '1'
2. `_teksttv_content` = wpautop na platslaan van alle whitespace naar 1 spatie (besluit eigenaar: multi-alinea was nooit de bedoeling; altijd exact 1 `<p>`)
3. `_teksttv_ai_body` = zelfde transformatie op content_gpt - identiek, anders klopt de audit niet

NIET nodig (onbenut in productie): `_teksttv_date_start/end`, `_teksttv_days`, `_teksttv_images`, `_teksttv_sidebar_image`, `_teksttv_title`, `_teksttv_category_image`.

Opties: klein genoeg om handmatig te zetten (2 kanalen, 3-5 blokken, 3 tickers). Vereist wel: `regio` toevoegen aan `teksttv_enabled_taxonomies` en de teksttv-wp-extensions plugin voor de FM/TV-tickers.

Openstaand risico: werkt het fine-tuned OpenAI-model via de AI Client / ai-provider-for-openai? Zo niet: terugvallen op een standaardmodel of de prompt-tuning herzien.

## Testresultaat migratiescript (tegen de dump-kopie)

18.131 posts gemigreerd, 4.548 met `_teksttv_ai_body`, waarvan 1.285 "Ongewijzigd" volgens de audit-logica van de nieuwe plugin (trim-gelijkheid; 1 post meer dan voor het platslaan doordat een paar alleen in whitespace verschilde). Na platslaan: 0 posts met meerdere `<p>`'s of `<br>`.
