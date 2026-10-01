# TODO: NDW-data pipeline lokaal opzetten

## 1. Projectstructuur voorbereiden

- [x] Maak de volgende mappen aan:

  ```text
  data/
  ├── minio/
  ├── postgres/
  └── exports/

  dbt/
  └── scripts/
  ```

- [x] Voeg een `.env`-bestand toe voor lokale configuratie en wachtwoorden.
- [x] Voeg `.env`, lokale exports en tijdelijke bestanden toe aan `.gitignore`.
- [x] Leg versies van Docker, PostgreSQL, MinIO en dbt vast.

## 2. Docker Compose maken

- [x] Maak een `docker-compose.yml` aan.
- [x] Voeg een MinIO-container toe.
- [x] Voeg een PostgreSQL-container toe.
- [x] Gebruik permanente lokale opslag voor MinIO en PostgreSQL.
- [x] Plaats beide services op hetzelfde interne Docker-netwerk.
- [x] Stel healthchecks in.
- [x] Configureer lokaal:
  - MinIO API: `http://localhost:9000`
  - MinIO webinterface: `http://localhost:9001`
  - PostgreSQL: `localhost:5433` (containerpoort blijft `5432`)
- [x] Start de omgeving met `docker compose up -d` en controleer dat beide
  services `healthy` zijn.
- [x] Controleer de logs en healthstatus van beide containers.

## 3. MinIO inrichten

- [x] Open de MinIO-webinterface.
- [x] Maak bucket `ndw-data` aan.
- [x] Maak de Bronze-structuur aan:

  ```text
  ndw-data/
  └── bronze/
      └── intensiteit-snelheid/
          └── YYYY/MM/
  ```

- [x] Leg vast welke MinIO-gebruikers en toegangsrechten nodig zijn:
  - `ndw_minio_admin`: bestaand root-account; uitsluitend voor lokaal beheer,
    bucketbeheer en het aanmaken van serviceaccounts.
  - `ndw_ingest`: serviceaccount voor de ingestie; alleen objecten lezen,
    toevoegen en lijsten in `ndw-data/bronze/*`. Geen verwijder- of
    beheerrechten.
  - `ndw_transform`: serviceaccount voor een toekomstig ingestie- of
    validatiescript; alleen lezen en lijsten in `ndw-data/bronze/*`.
  - dbt en Lightdash krijgen geen MinIO-account: zij gebruiken uitsluitend
    PostgreSQL nadat de Bronze-ingestie is uitgevoerd.
- [x] Maak `ndw_ingest` en `ndw_transform` aan met deze beperkte policies zodra
  het ingestiescript wordt gebouwd.
- [x] Test uploaden en downloaden van een klein testbestand.

## 4. PostgreSQL inrichten

- [x] Maak databaseschema’s aan:

  ```text
  bronze
  silver
  gold
  ```

- [x] Maak een technische tabel voor ingestiebatches.
- [x] Leg minimaal vast: batch-id, aanvraag-id, bestandsnaam, checksum,
  ingestietijdstip, bronperiode en aggregatievariant.
- [x] Test de verbinding vanaf de lokale computer.
- [x] Test de verbinding vanaf een tijdelijk dbt-project.

## 5. Eerste CSV ontvangen en registreren

- [ ] Controleer of de CSV overeenkomt met het datacontract in `PLAN.md`.
- [ ] Controleer delimiter, encoding, kolomnamen, datumformaat en decimalen.
- [ ] Leg de exportmetadata vast:
  - aanvraag-ID;
  - exportnaam;
  - bronperiode;
  - aggregatieperiode: uur;
  - aggregatievariant: ongewogen;
  - meetcompleetheid: niet meegenomen.
- [ ] Bereken een checksum van het originele bestand.
- [ ] Upload het originele bestand ongewijzigd naar de MinIO-Bronze-bucket.
- [ ] Registreer de batch in PostgreSQL.

## 6. Bronze-ingestie bouwen

- [x] Maak een ingestiescript dat een CSV uit MinIO leest.
- [x] Laad het bestand brongetrouw in een Bronze-tabel.
- [x] Voeg technische metadata toe aan iedere batch of record waar nodig.
- [x] Maak ingestie herhaalbaar zonder dezelfde batch dubbel te laden.
- [x] Log aantallen gelezen, geladen en afgewezen records.
- [ ] Test een herstart van de containers.
- [x] Test een dubbele upload.

## 7. dbt-project opzetten

- [x] Maak een dbt-project aan met de PostgreSQL-adapter.
- [x] Configureer verbinding met PostgreSQL.
- [ ] Richt sources in voor de Bronze-tabellen.
- [ ] Maak staging-modellen voor gestandaardiseerde namen en datatypes.
- [ ] Maak Silver-modellen voor:
  - meetresultaten;
  - meetlocaties en locatiekenmerken;
  - referentiewaarden;
  - datakwaliteit.
- [ ] Voeg model- en kolombeschrijvingen toe.

## 8. dbt-tests en datakwaliteit

- [ ] Test verplichte velden zoals `id_meetlocatie` en meetperiode.
- [ ] Test dat starttijd vóór eindtijd ligt.
- [ ] Test de voorlopige grain:
  `id_meetlocatie`, meetperiode, richting, rijbaan en voertuigcategorie.
- [ ] Test dat numerieke waarden correct worden ingelezen.
- [ ] Test geldige grenzen voor latitude en longitude.
- [ ] Test negatieve waarden in gemiddelden, aantallen, minuten en spreiding.
- [ ] Test kwaliteitsindicatoren en foutvelden.
- [ ] Onderzoek dubbele records; verwijder ze niet automatisch.
- [ ] Maak een datakwaliteitsrapport voor ontbrekende en incomplete waarnemingen.

## 9. Gold-laag bouwen

- [ ] Maak een Gold-model voor gemiddelde intensiteit per uur en locatie.
- [ ] Maak een Gold-model voor gemiddelde snelheid per uur en locatie.
- [ ] Maak een Gold-model voor gewogen gemiddelde snelheid.
- [ ] Maak een Gold-model voor spreiding en datakwaliteit.
- [ ] Voeg afgeleide velden toe zoals meetdatum, meetuur en weekdag.
- [ ] Documenteer dat de bronaggregatie ongewogen is.
- [ ] Valideer Gold-uitkomsten met steekproeven uit de CSV.

## 10. Lightdash toevoegen

- [ ] Voeg Lightdash toe aan Docker Compose zodra de Gold-tabellen stabiel zijn.
- [ ] Configureer de PostgreSQL-verbinding.
- [ ] Koppel Lightdash aan het Gold-schema.
- [ ] Definieer metrics en dimensies in de dbt-modellen.
- [ ] Maak een dashboard met:
  - intensiteitstrends;
  - snelheidstrends;
  - filters voor periode, locatie, richting en voertuigcategorie;
  - datadekking en kwaliteitsindicatoren.
- [ ] Valideer de cijfers met een inhoudelijke gebruiker.

## 11. Operationeel maken

- [ ] Documenteer starten, stoppen, back-up en herstel van de lokale omgeving.
- [ ] Leg de pipelinevolgorde vast:
  `upload → registratie → Bronze → dbt Silver → tests → Gold → Lightdash`.
- [ ] Voeg logging en foutmeldingen toe.
- [ ] Beschrijf hoe een nieuwe export en historische backfill worden verwerkt.
- [ ] Leg bewaartermijn, AVG-maatregelen en toegangsrechten vast.
- [ ] Herbeoordeel PostgreSQL en lokale MinIO-opslag bij groei van volume of
  gebruik; migreer dan eventueel naar beheerde objectopslag en een cloud
  warehouse.

## Eerste concrete werksessie

1. Docker Compose maken voor MinIO en PostgreSQL.
2. Containers starten en verbindingen testen.
3. Bucket `ndw-data` en schema’s `bronze`, `silver` en `gold` maken.
4. CSV uploaden zodra deze beschikbaar is.
5. Eerste Bronze-tabel en dbt-stagingmodel bouwen.
