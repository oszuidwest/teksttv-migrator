# teksttv-migrator

Eenmalige migratie van Tekst TV in het [Streekomroep-thema](https://github.com/oszuidwest/streekomroep-wp) en [`zw-ttvgpt`](https://github.com/oszuidwest/zw-ttvgpt) naar de zelfstandige [TekstTV-plugin](https://github.com/oszuidwest/teksttv-wp-plugin).

## Bestanden

- `migrate-teksttv-posts.php`: WP-CLI-script voor de berichtmeta
- `analysis/analyze.sql`: analysequeries voor een lokale databasekopie
- `analysis/FINDINGS.md`: bevindingen uit de productiedump van 4 augustus 2026

## Vereisten

- WordPress 7.0 of nieuwer
- PHP 8.3 of nieuwer
- WP-CLI op de server of in de beheercontainer
- Een recente databaseback-up buiten de webroot en deze repository
- De releasebestanden van TekstTV en [TekstTV Streekomroep Extensions](https://github.com/oszuidwest/teksttv-wp-extensions)

Controleer voor ieder commando het WordPress-pad en de omgeving:

```bash
wp core version --path=/path/to/wordpress
wp option get home --path=/path/to/wordpress
```

Voeg bij multisite ook `--url=<site-url>` toe. De voorbeelden hieronder gaan uit van een single-site-installatie.

## Installatie

Gebruik de gepubliceerde releases. Een Git-checkout van TekstTV bevat niet automatisch `vendor/` en de gebouwde adminbestanden.

Installeer beide plugins via het WordPress-beheer of met WP-CLI:

```bash
wp plugin install /secure/path/teksttv-<version>.zip --path=/path/to/wordpress
wp plugin install /secure/path/teksttv-wp-extensions-<version>.zip --path=/path/to/wordpress
```

Controleer daarna of de hoofdbestanden hier staan:

```text
wp-content/plugins/teksttv/teksttv.php
wp-content/plugins/teksttv-wp-extensions/teksttv-wp-extensions.php
```

De migrator is geen plugin. Plaats `migrate-teksttv-posts.php` tijdelijk buiten de webroot en voer het script met een absoluut pad uit. Verwijder het na de migratie van de server.

De migratie heeft alleen WordPress core nodig. TekstTV en de extensie mogen nog inactief zijn. Activeer voor de configuratie en feedcontrole eerst TekstTV en daarna de extensie.

## Gemigreerde gegevens

Het script selecteert alle niet-verwijderde berichten van het type `post` met `post_in_kabelkrant = 1` en niet-lege kabelkrantcontent.

| Bronveld | Doelveld | Bewerking |
| --- | --- | --- |
| `post_in_kabelkrant` = `1` | `_teksttv_active` = `1` | Selectie en activatie |
| `post_kabelkrant_content` | `_teksttv_content` | Whitespace samenvoegen en daarna `wpautop`; altijd één `<p>` |
| `post_kabelkrant_content_gpt` | `_teksttv_ai_body` | Dezelfde bewerking, als een AI-baseline aanwezig is |

Dezelfde bewerking voor content en AI-baseline is nodig voor de bestaande `trim()`-vergelijking in de AI-audit.

Deze gegevens worden niet gemigreerd omdat ze volgens de productieanalyse niet werden gebruikt:

- begin- en einddatum en weekdagen
- extra afbeeldingen en categorie-afbeeldingen
- campagnes en campagnegroepen
- kanaal-, loop-, ticker-, weer-, preview- en AI-instellingen

Stel deze configuratie tijdens de cutover handmatig in.

## Gebruik

Begin altijd met een dry-run. Zonder het argument `migrate` schrijft het script niets.

```bash
# Volledige dry-run
wp eval-file /secure/path/migrate-teksttv-posts.php --path=/path/to/wordpress

# Eerste 100 kandidaten testen
wp eval-file /secure/path/migrate-teksttv-posts.php limit=100 --path=/path/to/wordpress
wp eval-file /secure/path/migrate-teksttv-posts.php migrate limit=100 --path=/path/to/wordpress

# Volledige migratie
wp eval-file /secure/path/migrate-teksttv-posts.php migrate --path=/path/to/wordpress

# Bestaande doelcontent overschrijven
wp eval-file /secure/path/migrate-teksttv-posts.php migrate overwrite --path=/path/to/wordpress
```

Zonder `overwrite` blijft bestaande `_teksttv_content` staan. Het script herstelt wel ontbrekende `_teksttv_active`- en `_teksttv_ai_body`-velden. Een opgeslagen `_teksttv_active = 0` blijft behouden. Daardoor kan een afgebroken migratie veilig opnieuw worden gestart.

Met `overwrite` wordt de oude bron opnieuw leidend. Daarbij kan ook een verouderde `_teksttv_ai_body` worden verwijderd. Gebruik dit alleen zolang niemand de content in TekstTV heeft aangepast.

Onbekende argumenten, queryfouten en mislukte metawijzigingen stoppen het script. Berichtmeta wordt in batches gelezen; de gedeelde objectcache wordt niet geleegd.

## Verwachte dry-run

De eerste dry-run op de productiedump van 4 augustus 2026 gaf:

```text
Would migrate content: 18131
Preserved existing _teksttv_content: 0
Would set/repair _teksttv_active: 18131
Would set/repair AI baselines: 4548
Would remove stale AI baselines: 0
Source posts with AI baseline: 4548
  of which unmodified vs content (audit check): 1285
```

Na een volledige migratie hoort een nieuwe dry-run geen wijzigingen meer voor te stellen:

```text
Would migrate content: 0
Preserved existing _teksttv_content: 18131
Would set/repair _teksttv_active: 0
Would set/repair AI baselines: 0
Would remove stale AI baselines: 0
Source posts with AI baseline: 4548
  of which unmodified vs content (audit check): 1285
```

De aantallen kunnen afwijken als na 4 augustus 2026 nieuwe bronberichten zijn toegevoegd.

## Productierunbook

### Voorbereiding

1. Kondig een kort redactieslot aan of houd de tijd tussen migratie en cutover zo kort mogelijk.
2. Controleer `--path` en bij multisite ook `--url`.
3. Maak een databaseback-up op een afgeschermde locatie:

   ```bash
   wp db export /secure/backup/path/before-teksttv-migration.sql --path=/path/to/wordpress
   ```

4. Installeer TekstTV en TekstTV Streekomroep Extensions. Laat ze zo nodig nog inactief.
5. Plaats de migrator tijdelijk buiten de webroot.

### Berichtmeta migreren

1. Draai de volledige dry-run en controleer de totalen.
2. Onderzoek onverwachte verschillen voordat je gegevens schrijft.
3. Draai de migratie zonder `overwrite`.
4. Draai meteen opnieuw een dry-run. Alle voorgestelde wijzigingen moeten nul zijn.

Wijzigingen in het oude systeem worden na de migratie niet automatisch gekopieerd. Gebruik daarom een redactieslot. Een laatste `migrate overwrite` vlak voor de cutover kan alleen als de nieuwe TekstTV-content nog niet handmatig is bewerkt.

### Plugins configureren

1. Activeer eerst **TekstTV** en daarna **TekstTV Streekomroep Extensions**.
2. Controleer of het Streekomroep-thema actief is.
3. Open **Tekst TV** en daarna **Instellingen**. Stel daar het volgende in:
   - kanalen `tv1` en `tv2`
   - features en standaardweergaveduren
   - taxonomie `regio`
   - OpenWeather One Call 3.0-sleutel
   - volledige preview-URL
4. Open **Inhoud & AI** en stel het volgende in:
   - een provider via WordPress Connectors
   - provider, model en prompts
   - `regio` als taxonomie voor de regioprefix
   - woord- en tekenlimieten
5. Controleer of de provider het eerder gebruikte fine-tuned model ondersteunt. Kies anders een ondersteund model en beoordeel de output opnieuw.
6. Bouw de loops voor `tv1` en `tv2` opnieuw op. De blokken en regiofilters staan in `analysis/FINDINGS.md`.
7. Voeg in deze volgorde **Nu op FM**, **Vandaag op TV** en **Straks op FM** toe. **Morgen op TV** was in de oude configuratie niet in gebruik.
8. Maak alleen nieuwe campagnes en campagnegroepen aan als ze nodig zijn. De oude campagnes waren verlopen.

Sla een tickerconfiguratie met extensietypen niet op als de extensie uitstaat. TekstTV kan onbekende typen dan verwijderen.

### Feed en frontend controleren

Controleer eerst de REST-feed zonder de frontend:

```bash
curl --fail --silent --show-error \
  'https://<wordpress-host>/wp-json/teksttv/v1/slides?channel=tv1'

curl --fail --silent --show-error \
  'https://<wordpress-host>/wp-json/teksttv/v1/slides?channel=tv2'
```

Controleer voor beide kanalen:

- recente artikelen en de juiste regioselectie
- één alinea per gemigreerde tekst
- weer en tickerberichten
- afbeeldingen en lege resultaten
- 4.548 AI-baselines en, voor deze dump, 1.285 ongewijzigde teksten

Stel daarna de API-basis-URL van de frontend in, deploy de frontend en controleer de live- en previewweergave van beide kanalen.

### Cutover en opruimen

1. Stop wijzigingen in het oude systeem en voer alleen indien veilig de laatste `overwrite` uit.
2. Herhaal de dry-run en de controles van REST-feed en frontend.
3. Zet de frontend om naar de nieuwe REST-feed.
4. Deploy de goedgekeurde cleanup van het Streekomroep-thema.
5. Verwijder oude postmeta en opties pas na de eindcontrole. Dit geldt onder andere voor `post_kabelkrant_datum_in`, `ttvgpt_api_key`, `ttvgpt_model` en `ttvgpt_word_limit`.
6. Deactiveer en verwijder `zw-ttvgpt`.
7. Roteer de huidige en oude OpenAI-credentials uit de productiedump.
8. Verwijder de migrator en tijdelijke database-exporten van de server.

## Rollback

Ruim het oude systeem pas op nadat de nieuwe feed en frontend zijn goedgekeurd. Zolang de oude code en bronmeta nog bestaan, is de snelle rollback:

1. Zet de frontend terug naar de oude databron.
2. Deactiveer TekstTV Streekomroep Extensions en TekstTV.
3. Laat het oude systeem actief.

De nieuwe `_teksttv_*`-meta doet zonder TekstTV niets en hoeft voor deze rollback niet te worden verwijderd. Herstel de databaseback-up als de oude data al is opgeschoond of andere productiedata is gewijzigd.

## Productiedata

Werk alleen met een afgeschermde lokale kopie van de productiedatabase. Commit of deel nooit de dump, database-identifiers, credentials of ongeschoonde queryuitvoer. `analysis/analyze.sql` maskeert bekende AI-instellingen, maar controleer de uitvoer alsnog voordat je die deelt. Verwijder de lokale dump na afloop of bewaar hem versleuteld en met beperkte toegang.

Het script is getest op de databasekopie van 4 augustus 2026: 18.131 berichten en 4.548 AI-baselines, waarvan 1.285 ongewijzigd. Alle gemigreerde teksten kwamen uit op één alinea.
