# NDW-data: medallion-architectuur

## Doel

Een herhaalbare datapijplijn bouwen voor NDW-data over gemiddelde intensiteit en
snelheid. De pijplijn verwerkt de brondata van ongewijzigde landing tot
gevalideerde datasets en dashboards in Lightdash.

## Architectuur

`Bronbestand → Bronze → dbt Silver → Gold → Lightdash`


## Eerste datacontract

De aangeleverde kolommen zijn voldoende om de eerste Bronze-laag en een eerste
dbt-model op te zetten. De export bevat drie soorten informatie:

### 1. Meetresultaat en periode

- `id_meetlocatie`, `versie_meetlocatie`, `ndw_index`
- `start_meetperiode`, `eind_meetperiode`, `meetperiode`
- `gem_intensiteit`, `gem_snelheid`, `gewogen_gem_snelheid`
- `spreiding_intensiteit`, `spreiding_snelheid`
- `waarnemingen_intensiteit`, `waarnemingen_snelheid`
- `incomplete_waarnemingen_intensiteit`, `incomplete_waarnemingen_snelheid`
- `gebruikte_minuten_intensiteit`, `gebruikte_minuten_snelheid`
- `kwaliteitsindicator_intensiteit`, `kwaliteitsindicator_snelheid`
- `data_error_intensiteit`, `data_error_snelheid`

### 2. Meetconfiguratie en verkeerscontext

- `gebruikte_rekenmethode_intensiteit`, `gebruikte_rekenmethode_snelheid`
- `standaard_rekenmethode`, `gebruikte_meetapparatuur`, `nauwkeurigheid`
- `rijrichting`, `rijstrook_rijbaan`, `specifieke_baan`, `voertuigcategorie`
- `totaal_aantal_rijstroken`

### 3. Locatie, VILD en OpenLR

- Meetlocatie: `naam_meetlocatie`, `naam_meetlocatie_mst`, `voorganger`, `opvolger`
- Coördinaten: `start_locatie_latitude`, `start_locatie_longitude`,
  `locatie_latitude_openlr`, `locatie_longitude_openlr`
- VILD: `versie_vild`, `subversie_vild`, `richting_in_vild`, `locatiecode_vild`,
  `afstand_tot_vild_locatie`, `wegnummer_vild`, `wegnaam_vild`, `1e_naam_vild`,
  `2e_naam_vild`
- Wegpositie: `positie_tov_weg`, `positie_tov_rijrichting`,
  `afstand_vanaf_het_referentiepunt`, `hoek_graden_van_ref_punt_naar_exacte_loc`
- Wegclassificatie: `wegclassificatie_1`, `wegclassificatie_2`,
  `laagste_wegclassificatie`, `afstand_tussen_eerste_en_laatste_punt_ref_lijn`

### 4. Levering en referentiewaarden

- `starttijd_leveringsperiode`, `gecalculeerde_starttijd_leveringsperiode`
- `type_referentiewaarde`, `referentiewaarde_gem_intensiteit`,
  `referentiewaarde_gem_snelheid`
- `landcode`

## Wat we nu al kunnen voorbereiden

1. **Bronnencontract:** vastleggen dat deze kolommen verplicht, optioneel of
   conditioneel zijn en welke datatype-, eenheids- en betekenisdefinitie ze
   hebben.
2. **Bronze-schema:** alle velden aanvankelijk als brongetrouw opslaan, inclusief
   batch-id, bestandsnaam en ingestietijdstip.
3. **Silver-modellen:** een staging-tabel met gestandaardiseerde namen en typen,
   plus afzonderlijke modellen voor meetresultaten, meetlocaties en
   referentiewaarden.
4. **Grain bepalen:** voorlopig één record per combinatie van
   `id_meetlocatie`, `start_meetperiode`, `eind_meetperiode`, `rijrichting`,
   `rijstrook_rijbaan` en `voertuigcategorie`. Dit moet met de eerste export
   worden gecontroleerd.
5. **Eerste Gold-KPI’s:** gemiddelde intensiteit, gemiddelde snelheid, gewogen
   gemiddelde snelheid, spreiding, datakwaliteit en volledigheid per periode,
   locatie, richting en voertuigcategorie.

## Eerste dbt-validaties

- Controleer dat `id_meetlocatie`, `start_meetperiode` en `eind_meetperiode`
  aanwezig zijn.
- Controleer dat `start_meetperiode` vóór `eind_meetperiode` ligt.
- Controleer dat numerieke velden als getal worden ingelezen en coördinaten
  binnen geldige geografische grenzen vallen.
- Controleer dat gemiddelden, spreidingen, aantallen en minuten niet negatief
  zijn, tenzij de brondefinitie dit expliciet toestaat.
- Controleer de uniciteit van de voorlopige grain; dubbele records moeten worden
  onderzocht en niet automatisch verwijderd.
- Controleer de relatie tussen `waarnemingen_*`, `gebruikte_minuten_*` en de
  kwaliteits- en foutindicatoren.
- Controleer of referentiewaarden alleen voorkomen wanneer
  `type_referentiewaarde` is gevuld.

De exacte datatypes, eenheden, toegestane codes en kwaliteitsgrenzen worden
vastgesteld zodra een representatieve export beschikbaar is.

## Metadata van de eerste exportaanvraag

De eerste export is aangevraagd met de volgende metadata:

| Eigenschap | Waarde |
|---|---|
| Aanvraag-ID | `00000000-0000-4000-8000-000000000001` (voorbeeld) |
| Soort aanvraag | Actuele Verkeersgegevens |
| Periodieke aanvraag | Nee |
| Naam | `intensiteit-snelheid-export` |
| Aangemaakt op | 21 september 2026, 15:04:17 |
| Periode | 1 januari 2024 t/m 21 september 2026, 00:00:00–23:59:59 |
| Dagen | Maandag t/m zondag |
| Meetcompleetheid | Niet meegenomen |
| Formaat | CSV |
| Aggregatieperiode | Uur |
| Aggregatievariant | Ongewogen |

### Consequenties voor de pipeline

- Bewaar deze aanvraagmetadata samen met de Bronze-batch; de aanvraag-ID is een
  belangrijke bron- en lineage-identificatie.
- Behandel de export als een eenmalige momentopname. De aanvraag is niet
  periodiek, dus nieuwe exports krijgen een nieuwe batch en moeten expliciet
  worden ingelezen.
- Modelleer de tijdsgranulariteit als uur. Gebruik `start_meetperiode` en
  `eind_meetperiode` om de duur te controleren en maak een afgeleide
  `meetdatum` en `meetuurnummer` voor analyses.
- Neem in dashboards op dat de aggregatie ongewogen is. Een dag- of
  maandgemiddelde mag niet zonder inhoudelijke keuze uit de uurregels worden
  berekend; controleer eerst of een gewogen berekening op basis van waarnemingen
  of gebruikte minuten nodig is.
- Omdat meetcompleetheid niet is meegenomen, moeten de velden voor incomplete
  waarnemingen en kwaliteitsindicatoren actief worden gebruikt voor filtering en
  datakwaliteitsrapportage.
- Controleer of de einddatum inclusief is en of de tijdzone en zomer-/wintertijd
  expliciet zijn vastgelegd. Dit is vooral belangrijk bij uurlijkse records.

### Aanvullende Bronze-metadata

Naast de kolommen uit het datacontract slaan we per batch minimaal op:

- `aanvraag_id`;
- `exportnaam`;
- `aangevraagd_op`;
- `bron_periode_van` en `bron_periode_tot`;
- `aggregatieperiode` en `aggregatievariant`;
- `periodieke_aanvraag` en `meetcompleetheid_meegenomen`;
- bestandsnaam, bestandsgrootte, checksum en `ingestion_timestamp`.

## Stappenplan

### 1. Scope en brondata vastleggen

- Definieer de eerste use-cases en de gewenste KPI’s.
- Leg vast welke velden, eenheden, periode, meetlocatie en granulariteit in de
  export voor gemiddelde intensiteit en snelheid zitten.
- Ontvang het exportbestand en documenteer bron, aanleverdatum, bestandsformaat
  en eventuele AVG/privacybeperkingen.

**Resultaat:** een beschreven bronbestand met een eerste datacontract.

### 2. Bronze-laag inrichten

- Sla het originele bestand ongewijzigd op in een datumgebonden locatie.
- Voeg technische metadata toe, zoals `ingestion_timestamp`, bronbestand en
  batch-id.
- Maak ingestion herhaalbaar en voorkom dubbele batches.
- Controleer alleen basale technische eigenschappen: bestand leesbaar, verplichte
  kolommen aanwezig en datatypes herkenbaar.

**Resultaat:** reproduceerbare, onveranderde Bronze-data.

### 3. dbt-project en Silver-laag bouwen

- Richt een dbt-project in met sources, staging-modellen en tests.
- Normaliseer kolomnamen en datatypes; maak tijdstempels, locatie-identifiers en
  eenheden expliciet.
- Behandel ontbrekende waarden, dubbele records en ongeldige meetwaarden volgens
  vastgelegde regels.
- Voeg documentatie en tests toe voor `not_null`, `unique`, relaties en
  plausibiliteitsgrenzen.
- Gebruik incrementele verwerking zodra de omvang of aanleverfrequentie dat
  rechtvaardigt.

**Resultaat:** betrouwbare, opgeschoonde Silver-tabellen met lineage.

### 4. Gold-laag modelleren

- Ontwerp een eenvoudig analytisch model met duidelijke fact- en dimensietabellen.
- Maak consumptietabellen voor minimaal:
  - gemiddelde intensiteit per periode en meetlocatie;
  - gemiddelde snelheid per periode en meetlocatie;
  - datakwaliteit en dekking per periode.
- Leg KPI-definities, aggregatieniveau en filters vast.
- Controleer de uitkomsten tegen steekproeven uit de brondata.

**Resultaat:** stabiele, dashboardklare Gold-datasets.

### 5. Orchestratie en operationeel maken

- Maak de volgorde `ingestie → dbt build → tests → publicatie` expliciet.
- Plan de pipeline zodra de aanleverfrequentie bekend is.
- Laat publicatie naar Gold en Lightdash alleen doorgaan bij geslaagde tests.
- Leg logging, foutafhandeling, herstarten en historische backfills vast.

**Resultaat:** een gecontroleerde en herhaalbare pipeline.

### 6. Lightdash-dashboard bouwen

- Koppel Lightdash aan de Gold-laag.
- Maak een eerste dashboard met trends in intensiteit en snelheid, filters voor
  periode en locatie, en een overzicht van datadekking.
- Voeg definities en context toe aan metrics zodat gebruikers de cijfers juist
  interpreteren.
- Valideer het dashboard met een inhoudelijke gebruiker.

**Resultaat:** bruikbare visualisatie met herleidbare KPI’s.

## Eerste mijlpalen

1. Export ontvangen en datacontract ingevuld.
2. Eerste Bronze-batch opgeslagen.
3. dbt staging-modellen en basistests groen.
4. Gold-KPI’s gevalideerd tegen de bron.
5. Eerste Lightdash-dashboard gepubliceerd.

## Openstaande beslissingen

- Waar worden Bronze, Silver en Gold opgeslagen? **Voorlopige keuze: Bronze in
  S3-compatibele objectopslag; Silver en Gold in PostgreSQL.**
- Welke database/warehouse en dbt-adapter worden gebruikt? **Voorlopige keuze:
  PostgreSQL met `dbt-postgres`.**
- Hoe vaak komt nieuwe data binnen en hoe wordt een batch geïdentificeerd?
- Welke bewaartermijn en AVG-maatregelen gelden voor de brondata?
- Welke KPI-definities en kwaliteitsgrenzen moeten inhoudelijk worden goedgekeurd?

### Besluit 1: opslaglagen

De gebruikelijke scheiding is:

- **Bronze:** object storage zoals Amazon S3, Azure Blob/ADLS of een
  S3-compatibele oplossing zoals MinIO. Hier bewaren we het originele CSV-bestand
  onveranderd, inclusief aanvraagmetadata.
- **Silver en Gold:** tabellen of views in een analytische database/warehouse.
  dbt beheert hier de transformaties en lineage.

Voor dit project kiezen we voorlopig voor **S3-compatibele objectopslag voor
Bronze** en **PostgreSQL voor Silver en Gold**. Dat is eenvoudig te beheren voor
een eerste pipeline, ondersteunt CSV en sluit goed aan op een Lightdash-opzet.
Als Data Fryslân al een standaardoplossing heeft, gaat die organisatiekeuze
voor op deze technische default; dan blijft de architectuur hetzelfde.

### Besluit 2: database en dbt-adapter

We kiezen voorlopig voor **PostgreSQL + `dbt-postgres`**. Daarmee kunnen we:

- lokaal en in een beheerde omgeving dezelfde SQL-modellen gebruiken;
- dbt-tests, documentatie en lineage toepassen;
- Silver- en Gold-tabellen rechtstreeks aan Lightdash aanbieden;
- starten zonder direct een zwaar cloud data warehouse nodig te hebben.

Een groot cloud warehouse zoals BigQuery, Snowflake of Databricks is gebruikelijk
bij grotere volumes, veel gelijktijdige gebruikers of bestaande organisatie-
standaarden. Voor de huidige uurlijkse export is PostgreSQL de meest pragmatische
startkeuze. Herbeoordeling is nodig zodra volume, verversingssnelheid of
querybelasting duidelijk hoger wordt.

**Vast te leggen bij implementatie:** PostgreSQL-versie, database- en
schemanamen (`bronze`, `silver`, `gold`), opslaglocatie voor Bronze, en de
Lightdash-connectie met het `gold`-schema.
