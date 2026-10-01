# NDW-data medallion-pipeline

Lokale datapijplijn voor NDW-exports met gemiddelde verkeersintensiteit en
snelheid. Het project bewaart het originele CSV-bestand in MinIO, laadt iedere
bronrij ongewijzigd in de Bronze-laag van PostgreSQL en gebruikt dbt voor de
getypeerde Silver-laag en dashboardklare Gold-modellen.

> De lokale infrastructuur, streaming Bronze-ingestie, Silver- en
> Gold-modellen en Lightdash-service zijn werkend. Na de eerste start moet nog
> een persoonlijk Lightdash-account en project worden aangemaakt. Zie
> [TO_DO.md](TO_DO.md) voor de actuele voortgang.

## Architectuur

```text
NDW CSV
  │
  ▼
MinIO: ndw-data/bronze/intensiteit-snelheid/YYYY/MM/
  │
  ▼
PostgreSQL: bronze.ingestion_batches
            bronze.ndw_intensiteit_snelheid_raw
  │
  ▼
dbt: Silver → Gold
  │
  ▼
Lightdash: explores, grafieken en dashboards
```

- **Bronze in MinIO:** het originele bestand blijft ongewijzigd bewaard.
- **Bronze in PostgreSQL:** iedere CSV-rij wordt als JSONB opgeslagen, met een
  batch-id en bronregelnummer.
- **Silver:** gestandaardiseerde typen, opgeschoonde meetwaarden, lineage,
  meetlocatie-overzicht en afgeleide datakwaliteit.
- **Gold:** gededupliceerde uurdata en dashboardklare dag-KPI's voor
  intensiteit, snelheid, voertuigcategorieën en datadekking.

Meer achtergrond, het voorlopige datacontract en ontwerpbesluiten staan in
[PLAN.md](PLAN.md).

## Vereisten

- Docker met Docker Compose
- Python 3.11
- Lightdash CLI voor het publiceren van het dbt-project
- een NDW-export in CSV-formaat

De vastgelegde componentversies staan in [.env.example](.env.example). De
Python-afhankelijkheden zijn `dbt-postgres`, `boto3` en de bijbehorende
PostgreSQL-driver.

## Snel starten

### 1. Lokale configuratie maken

```bash
cp .env.example .env
```

Vervang in `.env` alle voorbeeldwachtwoorden. Gebruik voor `DBT_PASSWORD`
hetzelfde wachtwoord als voor `POSTGRES_PASSWORD`.

### 2. Python-omgeving maken

```bash
python3.11 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

### 3. Lokale services starten

```bash
docker compose up -d
docker compose ps
```

Wacht totdat de database- en opslagcontainers `healthy` zijn. De services zijn
daarna beschikbaar op:

| Service | Adres |
|---|---|
| MinIO API | <http://localhost:9000> |
| MinIO-console | <http://localhost:9001> |
| PostgreSQL | `localhost:5433` |
| Lightdash | <http://localhost:8080> |

De PostgreSQL-initialisatie maakt automatisch de schema's `bronze`, `silver`
en `gold` en de twee Bronze-tabellen aan. Dit gebeurt alleen bij de eerste
initialisatie van een leeg PostgreSQL-datavolume.

### 4. MinIO inrichten

Log in op de MinIO-console met `MINIO_ROOT_USER` en `MINIO_ROOT_PASSWORD` uit
`.env` en:

1. maak de bucket `ndw-data` aan;
2. maak een ingest-gebruiker of serviceaccount aan met de waarden
   `MINIO_INGEST_USER` en `MINIO_INGEST_PASSWORD`;
3. koppel de policy uit
   `minio/policies/ndw-ingest-bronze-read-write.json` aan dit account;
4. upload de CSV naar een datumgebonden objectpad, bijvoorbeeld:
   `bronze/intensiteit-snelheid/2026/09/export.csv`.

De ingest-policy staat alleen lezen, schrijven en lijsten binnen
`ndw-data/bronze/*` toe; verwijderen en bucketbeheer zijn niet toegestaan.

### 5. Verbinding met dbt controleren

```bash
./dbt/run_dbt.sh debug
```

Het dbt-profiel leest de database-instellingen uit `.env`.

## Een NDW-export inladen

Start de ingestie nadat de CSV in MinIO staat:

```bash
./scripts/run_ingest.sh \
  --object-key bronze/intensiteit-snelheid/2026/09/intensiteit-snelheid-export.csv \
  --exportnaam intensiteit-snelheid-export \
  --aanvraag-id 00000000-0000-4000-8000-000000000001 \
  --bron-periode-van 2024-01-01T00:00:00+01:00 \
  --bron-periode-tot 2026-09-21T23:59:59+02:00
```

Belangrijke opties:

| Optie | Verplicht | Standaardwaarde |
|---|---:|---|
| `--object-key` | ja | — |
| `--bucket` | nee | `ndw-data` |
| `--exportnaam` | nee | `intensiteit-snelheid-export` |
| `--aanvraag-id` | nee | — |
| `--bron-periode-van` | nee | — |
| `--bron-periode-tot` | nee | — |
| `--aggregatieperiode` | nee | `uur` |
| `--aggregatievariant` | nee | `ongewogen` |
| `--meetcompleetheid-meegenomen` | nee | `false` |
| `--delimiter` | nee | `,` |
| `--batch-size` | nee | `10000` |
| `--progress-every` | nee | `100000` |

Het script verwacht UTF-8 (een eventuele BOM wordt ondersteund), berekent een
SHA-256-checksum zonder het volledige bestand in het geheugen te laden en
registreert de batch in `bronze.ingestion_batches`. Vervolgens wordt de CSV
streaming gelezen en standaard per 10.000 rijen als JSONB weggeschreven naar
`bronze.ndw_intensiteit_snelheid_raw`. Met `--batch-size` kan de batchgrootte
worden aangepast; `--progress-every` bepaalt hoe vaak voortgang wordt getoond.

Een objectpad dat al met dezelfde checksum succesvol is geladen, wordt zonder
dubbele records overgeslagen. Een onderbroken of mislukte batch met dezelfde
checksum wordt hervat na de laatst volledig opgeslagen batch. Heeft hetzelfde
objectpad andere inhoud, dan stopt de ingestie; gebruik in dat geval een nieuw
datumgebonden objectpad.

Voor een CSV met een andere delimiter kan bijvoorbeeld `--delimiter ';'`
worden meegegeven.

## Resultaat controleren

Open een PostgreSQL-shell in de container:

```bash
docker compose exec postgres psql -U ndw_admin -d ndw
```

Voer vervolgens bijvoorbeeld uit:

```sql
SELECT
    batch_id,
    bron_bestandsnaam,
    bron_checksum_sha256,
    aantal_records_gelezen,
    aantal_records_geladen,
    status,
    ingestietijdstip
FROM bronze.ingestion_batches
ORDER BY ingestietijdstip DESC;

SELECT count(*)
FROM bronze.ndw_intensiteit_snelheid_raw;
```

Gebruik in het `psql`-commando een andere gebruiker of database als je de
standaardwaarden in `.env` hebt aangepast.

## dbt gebruiken

Alle dbt-commando's lopen via de wrapper, zodat `.env`, het projectpad en het
profielpad automatisch worden geladen:

```bash
./dbt/run_dbt.sh debug
./dbt/run_dbt.sh build
./dbt/run_dbt.sh docs generate
```

De dbt-keten bevat:

- `silver.stg_ndw_intensiteit_snelheid`: getypeerde staging-view;
- `silver.silver_ndw_meetresultaten`: incrementele Silver-feitentabel;
- `silver.silver_ndw_meetlocaties`: overzicht per meetlocatie en NDW-index;
- `silver.silver_ndw_datakwaliteit`: dagelijkse kwaliteitsverdeling.
- `gold.fct_ndw_verkeer_uur`: actuele uurmetingen voor alle categorieën;
- `gold.agg_ndw_verkeer_dag_totaal`: dag-KPI's voor `anyVehicle`;
- `gold.agg_ndw_verkeer_dag_voertuigcategorie`: categorieën afzonderlijk;
- `gold.agg_ndw_datakwaliteit_dag`: dagelijkse dekking en kwaliteit.

Een gewone `dbt build` verwerkt na de eerste volledige build alleen Bronze-
batches die nog niet in `silver_ndw_meetresultaten` voorkomen. Lege brontekst
wordt `NULL`; negatieve NDW-sentinelwaarden blijven beschikbaar in `*_raw`,
maar worden in de analysekolommen als `NULL` aangeboden.

Gebruik voor totale verkeerscijfers de Gold-tabel
`agg_ndw_verkeer_dag_totaal`. Deze gebruikt uitsluitend `anyVehicle`. De
voertuigcategorieën in de categorietabel kunnen overlappen en mogen niet bij
elkaar worden opgeteld. Dagintensiteit wordt alleen uit volledige, bruikbare
uurvakken opgebouwd; dagsnelheid wordt gewogen met het aantal
snelheidswaarnemingen.

## Lightdash gebruiken

Lightdash draait lokaal met een eigen applicatiedatabase en gebruikt een aparte
MinIO-bucket voor interne bestanden. Voor queries op NDW-data krijgt Lightdash
een PostgreSQL-account met uitsluitend leesrechten op schema `gold`.

Vul eerst alle `LIGHTDASH_*`-waarden in `.env` met eigen lokale geheimen. Richt
daarna de bucket, opslaggebruiker en PostgreSQL-reader in en start Lightdash:

```bash
./scripts/setup_lightdash.sh
```

Open vervolgens <http://localhost:8080> en maak het eerste beheerdersaccount
aan. Publiceer daarna het Gold-deel van het dbt-project vanuit de
Lightdash-container. Vervang het e-mailadres door het account dat je zojuist
hebt geregistreerd; het wachtwoord wordt interactief en verborgen gevraagd:

```bash
docker compose exec lightdash \
  lightdash login http://localhost:8080 --email jouw@email.nl

docker compose exec lightdash \
  lightdash deploy \
  --create "NDW Gold" \
  --project-dir /usr/app/dbt \
  --profiles-dir /usr/app/dbt \
  --target dev \
  --select tag:lightdash
```

De deploy gebruikt binnen Docker host `postgres:5432` en de read-only
inloggegevens uit `LIGHTDASH_WAREHOUSE_USER` en
`LIGHTDASH_WAREHOUSE_PASSWORD`. Herhaal na wijzigingen aan de Gold-modellen
alleen het tweede commando zonder `--create "NDW Gold"`.

De beschikbare Lightdash-tabellen zijn:

- **Dagverkeer totaal** voor totale intensiteit, gewogen snelheid en dekking;
- **Dagverkeer per voertuigcategorie** voor analyses per afzonderlijke
  categorie;
- **Datakwaliteit per dag** voor fouten en technische uitsluitingen;
- **Verkeer per uur** voor detailanalyses; deze tabel is groot en daarom minder
  geschikt als eerste dashboardbron.

Maak als eerste dashboard bijvoorbeeld een tijdreeks op `meetdatum` met
`Totale uurintensiteit` en `Gewogen gemiddelde snelheid`, plus filters voor
meetlocatie, richting en rijstrook. Gebruik voor categorieën een aparte tegel;
tel voertuigcategorieën niet bij elkaar op.

## Stoppen en logs bekijken

```bash
docker compose logs -f postgres minio lightdash lightdash-db
docker compose stop
```

Start de bestaande omgeving later opnieuw met:

```bash
docker compose start
```

`docker compose down` verwijdert de containers en het netwerk, maar de data
blijft in `data/postgres`, `data/minio` en `data/lightdash` staan. Verwijder
deze mappen niet als de lokale databases, dashboards en objecten behouden
moeten blijven.

## Projectstructuur

```text
.
├── data/                    # Lokale PostgreSQL-, MinIO- en exportdata (genegeerd)
├── dbt/                     # dbt-project, profiel en wrapper
├── minio/                   # MinIO-image en beperkte servicepolicies
├── scripts/                 # Ingestie- en lokale setupscripts
├── sql/                     # Eenmalige PostgreSQL-initialisatie
├── docker-compose.yml
├── PLAN.md                  # Architectuur, datacontract en ontwerpbesluiten
├── TO_DO.md                 # Implementatiestatus en vervolgstappen
└── requirements.txt
```

## Beveiliging en gegevensbeheer

- Commit `.env` nooit; dit bestand staat in `.gitignore`.
- Gebruik buiten lokale ontwikkeling geen root- of adminaccount voor ingestie.
- Vervang alle lokale Lightdash-voorbeeldgeheimen voordat de omgeving wordt
  gedeeld of buiten de eigen computer bereikbaar wordt gemaakt.
- De huidige verbindingen gebruiken HTTP naar MinIO en `sslmode=disable` voor
  PostgreSQL en zijn uitsluitend bedoeld voor lokaal gebruik.
- NDW-bronbestanden en lokale databasebestanden onder `data/` worden niet in
  versiebeheer opgenomen.
- Leg vóór productiegebruik bewaartermijnen, back-up/herstel, toegangsbeheer en
  eventuele privacymaatregelen vast.

## Bekende vervolgstappen

- het eerste Lightdash-dashboard samenstellen en inhoudelijk valideren;
- de volledige keten orchestreren: upload → Bronze → Silver → tests → Gold →
  Lightdash-publicatie.
