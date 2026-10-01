# NDW-data medallion-pipeline

Lokale datapijplijn voor NDW-exports met gemiddelde verkeersintensiteit en
snelheid. Het project bewaart het originele CSV-bestand in MinIO, laadt iedere
bronrij ongewijzigd in de Bronze-laag van PostgreSQL en gebruikt dbt als basis
voor de toekomstige Silver- en Gold-modellen.

> De lokale infrastructuur en Bronze-ingestie zijn werkend. De dbt-modellen
> voor Silver en Gold en de Lightdash-koppeling moeten nog worden gebouwd. Zie
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
Lightdash (gepland)
```

- **Bronze in MinIO:** het originele bestand blijft ongewijzigd bewaard.
- **Bronze in PostgreSQL:** iedere CSV-rij wordt als JSONB opgeslagen, met een
  batch-id en bronregelnummer.
- **Silver (gepland):** gestandaardiseerde namen, typen, meetresultaten,
  locaties, referentiewaarden en datakwaliteit.
- **Gold (gepland):** dashboardklare KPI's voor intensiteit, snelheid en
  datadekking.

Meer achtergrond, het voorlopige datacontract en ontwerpbesluiten staan in
[PLAN.md](PLAN.md).

## Vereisten

- Docker met Docker Compose
- Python 3.11
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

### 3. PostgreSQL en MinIO starten

```bash
docker compose up -d
docker compose ps
```

Wacht totdat beide containers `healthy` zijn. De services zijn daarna
beschikbaar op:

| Service | Adres |
|---|---|
| MinIO API | <http://localhost:9000> |
| MinIO-console | <http://localhost:9001> |
| PostgreSQL | `localhost:5433` |

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

Het script verwacht UTF-8 (een eventuele BOM wordt ondersteund), berekent een
SHA-256-checksum en registreert de batch in
`bronze.ingestion_batches`. De CSV-rijen komen brongetrouw als JSONB in
`bronze.ndw_intensiteit_snelheid_raw`.

Een objectpad dat al met dezelfde checksum succesvol is geladen, wordt zonder
dubbele records overgeslagen. Als hetzelfde pad andere inhoud heeft of bij een
onvoltooide batch hoort, stopt de ingestie met een foutmelding. Onderzoek dan de
bestaande batch of gebruik een nieuw datumgebonden objectpad.

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

Er staan momenteel nog geen inhoudelijke modellen in `dbt/models`. De eerstvolgende
stap is het toevoegen van een Bronze-source en staging-/Silver-modellen met
datakwaliteitstests.

## Stoppen en logs bekijken

```bash
docker compose logs -f postgres minio
docker compose stop
```

Start de bestaande omgeving later opnieuw met:

```bash
docker compose start
```

`docker compose down` verwijdert de containers en het netwerk, maar de data
blijft in `data/postgres` en `data/minio` staan. Verwijder deze mappen niet als
de lokale database en objecten behouden moeten blijven.

## Projectstructuur

```text
.
├── data/                    # Lokale PostgreSQL-, MinIO- en exportdata (genegeerd)
├── dbt/                     # dbt-project, profiel en wrapper
├── minio/                   # MinIO-image en beperkte ingest-policy
├── scripts/                 # Bronze-ingestiescript en wrapper
├── sql/                     # Eenmalige PostgreSQL-initialisatie
├── docker-compose.yml
├── PLAN.md                  # Architectuur, datacontract en ontwerpbesluiten
├── TO_DO.md                 # Implementatiestatus en vervolgstappen
└── requirements.txt
```

## Beveiliging en gegevensbeheer

- Commit `.env` nooit; dit bestand staat in `.gitignore`.
- Gebruik buiten lokale ontwikkeling geen root- of adminaccount voor ingestie.
- De huidige verbindingen gebruiken HTTP naar MinIO en `sslmode=disable` voor
  PostgreSQL en zijn uitsluitend bedoeld voor lokaal gebruik.
- NDW-bronbestanden en lokale databasebestanden onder `data/` worden niet in
  versiebeheer opgenomen.
- Leg vóór productiegebruik bewaartermijnen, back-up/herstel, toegangsbeheer en
  eventuele privacymaatregelen vast.

## Bekende vervolgstappen

- dbt-sources, staging- en Silver-modellen toevoegen;
- dbt-tests en een datakwaliteitsrapport implementeren;
- Gold-modellen en KPI-definities valideren;
- Lightdash aansluiten zodra de Gold-laag stabiel is;
- de volledige keten orchestreren: upload → Bronze → Silver → tests → Gold →
  publicatie.

