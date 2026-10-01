#!/usr/bin/env python3
"""Laad een NDW-CSV uit MinIO brongetrouw in de Bronze-laag."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import sys
import boto3
import psycopg2
from psycopg2.extras import execute_values


def environment(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Omgevingsvariabele {name} ontbreekt.")
    return value


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bucket", default="ndw-data")
    parser.add_argument("--object-key", required=True)
    parser.add_argument("--exportnaam", default="intensiteit-snelheid-export")
    parser.add_argument("--aanvraag-id")
    parser.add_argument("--bron-periode-van")
    parser.add_argument("--bron-periode-tot")
    parser.add_argument("--aggregatieperiode", default="uur")
    parser.add_argument("--aggregatievariant", default="ongewogen")
    parser.add_argument("--meetcompleetheid-meegenomen", action="store_true")
    parser.add_argument("--delimiter", default=",")
    return parser.parse_args()


def minio_client():
    endpoint = os.getenv("MINIO_ENDPOINT_URL", f"http://localhost:{environment('MINIO_API_PORT')}")
    return boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=environment("MINIO_INGEST_USER"),
        aws_secret_access_key=environment("MINIO_INGEST_PASSWORD"),
        region_name="us-east-1",
    )


def database_connection():
    return psycopg2.connect(
        host=environment("DBT_HOST"),
        port=environment("DBT_PORT"),
        dbname=environment("DBT_DATABASE"),
        user=environment("DBT_USER"),
        password=environment("DBT_PASSWORD"),
        sslmode="disable",
    )


def load_csv(client, bucket: str, object_key: str, delimiter: str):
    response = client.get_object(Bucket=bucket, Key=object_key)
    contents = response["Body"].read()
    checksum = hashlib.sha256(contents).hexdigest()
    decoded = contents.decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(decoded), delimiter=delimiter)
    if not reader.fieldnames:
        raise ValueError("CSV bevat geen kolomkoppen.")
    rows = list(reader)
    if not rows:
        raise ValueError("CSV bevat geen datarijen.")
    return checksum, reader.fieldnames, rows


def ingest(args: argparse.Namespace) -> str:
    checksum, fieldnames, rows = load_csv(
        minio_client(), args.bucket, args.object_key, args.delimiter
    )
    bestandsnaam = args.object_key.rsplit("/", maxsplit=1)[-1]
    connection = database_connection()

    try:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT batch_id, bron_checksum_sha256, status
                FROM bronze.ingestion_batches
                WHERE bron_object_key = %s
                """,
                (args.object_key,),
            )
            existing = cursor.fetchone()
            if existing:
                batch_id, existing_checksum, status = existing
                if existing_checksum == checksum and status == "loaded":
                    return f"Batch {batch_id} was al succesvol geladen; geen actie uitgevoerd."
                raise RuntimeError(
                    "Dit objectpad is al geregistreerd met andere inhoud of een onvoltooide batch. "
                    "Gebruik een nieuw, datumgebonden objectpad of onderzoek de bestaande batch."
                )

            cursor.execute(
                """
                INSERT INTO bronze.ingestion_batches (
                    aanvraag_id, exportnaam, bron_object_key, bron_bestandsnaam,
                    bron_checksum_sha256, bron_periode_van, bron_periode_tot,
                    aggregatieperiode, aggregatievariant,
                    meetcompleetheid_meegenomen, aantal_records_gelezen, status
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'loading')
                RETURNING batch_id
                """,
                (
                    args.aanvraag_id,
                    args.exportnaam,
                    args.object_key,
                    bestandsnaam,
                    checksum,
                    args.bron_periode_van,
                    args.bron_periode_tot,
                    args.aggregatieperiode,
                    args.aggregatievariant,
                    args.meetcompleetheid_meegenomen,
                    len(rows),
                ),
            )
            batch_id = cursor.fetchone()[0]
        connection.commit()

        try:
            with connection.cursor() as cursor:
                execute_values(
                    cursor,
                    """
                    INSERT INTO bronze.ndw_intensiteit_snelheid_raw (
                        batch_id, source_row_number, source_payload
                    ) VALUES %s
                    """,
                    [
                        (batch_id, row_number, json.dumps(row))
                        for row_number, row in enumerate(rows, start=2)
                    ],
                    page_size=1_000,
                )
                cursor.execute(
                    """
                    UPDATE bronze.ingestion_batches
                    SET status = 'loaded', aantal_records_geladen = %s,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE batch_id = %s
                    """,
                    (len(rows), batch_id),
                )
            connection.commit()
        except Exception as error:
            connection.rollback()
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    UPDATE bronze.ingestion_batches
                    SET status = 'failed', foutmelding = %s,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE batch_id = %s
                    """,
                    (str(error), batch_id),
                )
            connection.commit()
            raise
    finally:
        connection.close()

    return (
        f"Batch {batch_id} geladen: {len(rows)} rijen uit "
        f"s3://{args.bucket}/{args.object_key}; kolommen: {len(fieldnames)}."
    )


if __name__ == "__main__":
    try:
        print(ingest(arguments()))
    except Exception as error:
        print(f"Ingestie mislukt: {error}", file=sys.stderr)
        sys.exit(1)
