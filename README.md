# teksttv-migrator

Migratie van Tekst TV uit het Streekomroep-thema en `zw-ttvgpt` naar de zelfstandige TekstTV-plugin.

## Inhoud

- `migrate-teksttv-posts.php` — WP-CLI-migrator voor berichtmeta.
- `analysis/analyze.sql` — analysequeries voor een lokale databasekopie.
- `analysis/FINDINGS.md` — bevindingen uit de productiedump van 2026-08-04.

## Vereisten

- WordPress 7.0 of nieuwer.
- PHP 8.3 of nieuwer.
- WP-CLI op de server of in de gebruikte beheercontainer.
- Een actuele databaseback-up buiten de webroot en buiten deze repository.
- De release-ZIP van TekstTV en, voor de Streekomroep-tickers, de release-ZIP van TekstTV Streekomroep Extensions.

Controleer vóór ieder WP-CLI-commando dat het juiste WordPress-installatiepad en de juiste omgeving worden geraakt:

```bash
wp core version --path=/path/to/wordpress
wp option get home --path=/path/to/wordpress
```

Voeg bij multisite ook `--url=<site-url>` toe. De voorbeelden hieronder gaan uit van een single-site-installatie.

## Installatie en bestandslocaties

Gebruik bij voorkeur de gepubliceerde release-ZIP's; een ongebouwde Git-checkout van TekstTV mist `vendor/` en de gebouwde admin-assets.

Upload de plugins via **Plugins → Nieuwe plugin → Plugin uploaden**, of installeer ze inactief met WP-CLI:

```bash
wp plugin install /secure/path/teksttv-<version>.zip --path=/path/to/wordpress
wp plugin install /secure/path/teksttv-wp-extensions-<version>.zip --path=/path/to/wordpress
```

Na installatie horen de hoofdbestanden rechtstreeks in deze mappen te staan:

```text
wp-content/plugins/teksttv/teksttv.php
wp-content/plugins/teksttv-wp-extensions/teksttv-wp-extensions.php
```

De migrator is geen WordPress-plugin. Plaats `migrate-teksttv-posts.php` tijdelijk op een afgeschermde locatie, bij voorkeur buiten de webroot, en voer hem met een absoluut pad uit. Verwijder het bestand na de migratie van de server.

De berichtmigratie vereist alleen WordPress core. TekstTV en de extensie mogen tijdens de migratie nog inactief zijn. Voor configuratie en feedvalidatie moet TekstTV wel actief zijn; activeer de extensie daarna, omdat die van TekstTV en het actieve Streekomroep-thema afhankelijk is.

## Wat wordt gemigreerd

De migrator selecteert niet-verwijderde berichten van posttype `post` waarvoor `post_in_kabelkrant = 1` en niet-lege kabelkrantcontent aanwezig zijn.

| Bron (ACF) | Doel | Transformatie |
|----|----|----|
| `post_in_kabelkrant` = `1` | `_teksttv_active` = `1` | Selectiecriterium en activatie. |
| `post_kabelkrant_content` | `_teksttv_content` | Whitespace naar één spatie, daarna `wpautop`; exact één `<p>`. |
| `post_kabelkrant_content_gpt` | `_teksttv_ai_body` | Dezelfde transformatie, alleen bij een niet-lege AI-baseline. |

De identieke contenttransformatie zorgt dat de nieuwe AI-audit dezelfde `trim()`-vergelijking kan uitvoeren als de oude audit.

Niet gemigreerd, omdat deze velden volgens de productieanalyse niet werden gebruikt:

- begin-/einddatum en weekdagen;
- extra afbeeldingen en categorie-afbeeldingen;
- campagnes en campagnegroepen;
- kanaal-, loop-, ticker-, weer-, preview- en AI-instellingen.

Die configuratie wordt tijdens de cutover handmatig ingesteld.

## Commando's

```bash
# Volledige dry-run; schrijft niets.
wp eval-file /secure/path/migrate-teksttv-posts.php --path=/path/to/wordpress

# Werkelijke migratie.
wp eval-file /secure/path/migrate-teksttv-posts.php migrate --path=/path/to/wordpress

# Test de eerste 100 kandidaten.
wp eval-file /secure/path/migrate-teksttv-posts.php limit=100 --path=/path/to/wordpress
wp eval-file /secure/path/migrate-teksttv-posts.php migrate limit=100 --path=/path/to/wordpress

# Maak de oude bron opnieuw leidend; lees eerst de waarschuwing hieronder.
wp eval-file /secure/path/migrate-teksttv-posts.php migrate overwrite --path=/path/to/wordpress
```

Onbekende argumenten, queryfouten en niet-geslaagde metawijzigingen stoppen de run met een foutstatus. De migrator leest postmeta per batch en leegt nooit de gedeelde objectcache.

Zonder `overwrite` blijft bestaande `_teksttv_content` behouden. Ontbrekende `_teksttv_active`- en `_teksttv_ai_body`-velden worden wel hersteld, terwijl een bewust opgeslagen `_teksttv_active = 0` behouden blijft. Daardoor kan een onderbroken migratie veilig opnieuw worden gestart.

Met `overwrite` wordt de oude bron exact leidend, inclusief verwijdering van een stale `_teksttv_ai_body`. Gebruik dit alleen zolang niemand content in de nieuwe plugin heeft aangepast; anders kunnen handmatige wijzigingen verloren gaan.

## Verwachte dry-run

Voor de geanalyseerde productiedump gaf de eerste dry-run:

```text
Would migrate content: 18131
Preserved existing _teksttv_content: 0
Would set/repair _teksttv_active: 18131
Would set/repair AI baselines: 4548
Would remove stale AI baselines: 0
Source posts with AI baseline: 4548
  of which unmodified vs content (audit check): 1285
```

Dit betekent dat de doelmeta nog leeg is en alle kandidaten klaarstaan. Aantallen kunnen stijgen als na 2026-08-04 nieuwe bronberichten zijn toegevoegd.

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

## Productierunbook

### 1. Voorbereiden

1. Kondig een kort redactieslot aan of beperk de tijd tussen migratie en cutover.
2. Controleer `--path` en, bij multisite, `--url` tegen de bedoelde productieomgeving.
3. Maak een databaseback-up op een afgeschermde locatie:

   ```bash
   wp db export /secure/backup/path/before-teksttv-migration.sql --path=/path/to/wordpress
   ```

4. Installeer de release-ZIP's van TekstTV en TekstTV Streekomroep Extensions. Ze mogen nog inactief blijven.
5. Plaats de migrator tijdelijk buiten de webroot.

### 2. Berichtmeta migreren

1. Draai de volledige dry-run en vergelijk de totalen met de verwachte waarden hierboven.
2. Onderzoek onverwachte afwijkingen voordat er wordt geschreven.
3. Draai de werkelijke migratie zonder `overwrite`.
4. Draai direct daarna opnieuw de dry-run. Alle voorgestelde wijzigingen moeten nul zijn.

De migrator kan vóór pluginactivatie worden uitgevoerd. Wijzigingen die redacteuren daarna nog in het oude systeem maken, worden niet automatisch naar bestaande `_teksttv_content` gekopieerd. Gebruik daarom een redactieslot of voer vlak vóór cutover een laatste `migrate overwrite` uit, maar uitsluitend als de nieuwe TekstTV-content nog niet handmatig is bewerkt.

### 3. Plugins activeren en configureren

1. Activeer eerst **TekstTV** en daarna **TekstTV Streekomroep Extensions**.
2. Controleer dat het Streekomroep-thema actief is; zonder dat thema kan de extensie geen programmatickers registreren.
3. Configureer onder **Tekst TV → Instellingen**:
    - kanalen `tv1` en `tv2`;
    - gewenste features en standaardweergaveduren;
    - taxonomie `regio` als ingeschakelde taxonomie;
    - OpenWeather One Call 3.0-sleutel;
    - volledige preview-URL.
4. Configureer onder **Tekst TV → Inhoud & AI**:
    - een werkende provider via WordPress Connectors;
    - provider/model en prompts;
    - `regio` als taxonomie voor de regioprefix;
    - woord- en tekenlimieten.
5. Test expliciet of het eerder gebruikte fine-tuned model door de gekozen provider wordt ondersteund. Kies anders een ondersteund model en valideer de output opnieuw.
6. Bouw de loops voor `tv1` en `tv2` opnieuw op met weer- en artikelblokken en de regiofilters uit `analysis/FINDINGS.md`.
7. Configureer in deze volgorde de drie gebruikte tickertypen uit de extensie: **Nu op FM**, **Vandaag op TV**, **Straks op FM**. **Morgen op TV** is beschikbaar maar werd in de oude productieconfiguratie niet gebruikt.
8. Campagnes worden niet gemigreerd. Maak alleen actuele campagnegroepen en campagnes opnieuw aan wanneer ze nodig zijn; de oude campagnes waren verlopen.

Sla een tickerconfiguratie met extensietypen niet op terwijl de extensie gedeactiveerd is: onbekende typen kunnen dan uit de configuratie verdwijnen.

### 4. Feed en frontend valideren

Controleer eerst de REST-feed rechtstreeks, onafhankelijk van de frontend:

```bash
curl --fail --silent --show-error \
  'https://<wordpress-host>/wp-json/teksttv/v1/slides?channel=tv1'

curl --fail --silent --show-error \
  'https://<wordpress-host>/wp-json/teksttv/v1/slides?channel=tv2'
```

Controleer per kanaal minimaal:

- recente artikelen en correcte regiokeuze;
- één paragraaf per gemigreerde tekst;
- weerblok en tickerberichten;
- afbeeldingen en lege-resultaatsituaties;
- AI-audit: 4.548 bronbaselines en voor de geanalyseerde dump 1.285 ongewijzigde teksten.

Stel vervolgens de API-basis-URL in via de huidige, gedocumenteerde configuratiemethode van de TekstTV-frontend en deploy de frontend. Het aantal of de naam van frontendbronbestanden is bewust niet in dit runbook vastgelegd; dat is implementatiedetail van de frontendrelease. Valideer daarna de live- en previewweergave van beide kanalen.

### 5. Cutover en cleanup

1. Stop wijzigingen in het oude systeem en voer zo nodig de laatste veilige `overwrite` uit.
2. Herhaal de dry-run en de REST-/frontendcontroles.
3. Zet de frontend definitief om naar de nieuwe REST-feed.
4. Merge en deploy de goedgekeurde cleanup voor het Streekomroep-thema.
5. Ruim pas na geslaagde validatie de oude postmeta en legacy opties op, waaronder `post_kabelkrant_datum_in`, `ttvgpt_api_key`, `ttvgpt_model` en `ttvgpt_word_limit`.
6. Deactiveer en verwijder `zw-ttvgpt`.
7. Roteer alle huidige en legacy OpenAI-credentials die in de productiedump voorkwamen.
8. Verwijder `migrate-teksttv-posts.php` en eventuele tijdelijke database-exporten van de server.

## Rollback

Voer cleanup pas uit nadat de nieuwe feed en frontend zijn goedgekeurd. Zolang de oude code en bronmeta nog aanwezig zijn, bestaat de snelle rollback uit:

1. Frontend terugzetten naar de oude databron.
2. TekstTV Streekomroep Extensions en TekstTV deactiveren.
3. Het oude systeem actief laten.

De nieuwe `_teksttv_*`-meta is zonder de nieuwe plugin inert en hoeft voor een snelle rollback niet te worden verwijderd. Als de oude data al is opgeschoond of andere productiedata is gewijzigd, herstel dan de vooraf gemaakte databaseback-up volgens de geldende beheerprocedure.

## Omgaan met productiedata

Gebruik uitsluitend een afgeschermde, lokale kopie van de productiedatabase. Commit of deel nooit de dump zelf, database-identifiers, credentials of ongeschoonde uitvoer van de analysequeries. De bekende AI-instellingen worden door `analysis/analyze.sql` gemaskeerd, maar controleer alle uitvoer alsnog voordat die wordt gedeeld. Verwijder de lokale dump na afronding of bewaar hem versleuteld met zo beperkt mogelijke toegangsrechten.

De migrator is getest tegen de databasekopie van 2026-08-04: 18.131 berichten, 4.548 AI-baselines, waarvan 1.285 ongewijzigd. Alle gemigreerde teksten kwamen uit op exact één paragraaf.
