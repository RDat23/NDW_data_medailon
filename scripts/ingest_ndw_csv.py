#!/usr/bin/env python3
"""Laad een NDW-CSV uit MinIO streaming in de PostgreSQL Bronze-laag."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import sys
import time
from collections.abc import Iterator
from typing import Any

import boto3
import psycopg2
from psycopg2.extras import execute_values


CHECKSUM_CHUNK_SIZE = 8 * 1024 * 1024
DEFAULT_BATCH_SIZE = 10_000
DEFAULT_PROGRESS_EVERY = 100_000


def environment(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Omgevingsvariabele {name} ontbreekt.")
    return value


def positive_integer(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("waarde moet groter dan nul zijn")
    return parsed


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
    parser.add_argument("--batch-size", type=positive_integer, default=DEFAULT_BATCH_SIZE)
    parser.add_argument(
        "--progress-every",
        type=positive_integer,
        default=DEFAULT_PROGRESS_EVERY,
        help="Toon voortgang na dit aantal gelezen records.",
    )
    return parser.parse_args()


def minio_client():
    endpoint = os.getenv(
        "MINIO_ENDPOINT_URL", f"http://localhost:{environment('MINIO_API_PORT')}"
    )
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


def object_checksum(client, bucket: str, object_key: str) -> tuple[str, int]:
    """Bereken SHA-256 in constante geheugenruimte en controleer de objectgrootte."""
    response = client.get_object(Bucket=bucket, Key=object_key)
    expected_size = response.get("ContentLength")
    body = response["Body"]
    checksum = hashlib.sha256()
    bytes_read = 0

    try:
        for chunk in body.iter_chunks(chunk_size=CHECKSUM_CHUNK_SIZE):
            if not chunk:
                continue
            checksum.update(chunk)
            bytes_read += len(chunk)
    finally:
        body.close()

    if expected_size is not None and bytes_read != expected_size:
        raise RuntimeError(
            f"Onvolledige MinIO-read: verwacht {expected_size} bytes, "
            f"maar {bytes_read} bytes ontvangen."
        )
    return checksum.hexdigest(), bytes_read


def csv_rows(
    client, bucket: str, object_key: str, delimiter: str
) -> tuple[list[str], Iterator[tuple[int, dict[str, str]]], Any]:
    """Open de CSV als tekststream; de aanroeper sluit de geretourneerde stream."""
    response = client.get_object(Bucket=bucket, Key=object_key)
    text_stream = io.TextIOWrapper(response["Body"], encoding="utf-8-sig", newline="")
    reader = csv.DictReader(text_stream, delimiter=delimiter)
    if not reader.fieldnames:
        text_stream.close()
        raise ValueError("CSV bevat geen kolomkoppen.")

    def numbered_rows() -> Iterator[tuple[int, dict[str, str]]]:
        for source_row_number, row in enumerate(reader, start=2):
            if None in row:
                raise ValueError(
                    f"CSV-regel {source_row_number} bevat meer waarden dan kolommen; "
                    "controleer de delimiter en CSV-opmaak."
                )
            yield source_row_number, row

    return list(reader.fieldnames), numbered_rows(), text_stream


def existing_batch(connection, object_key: str):
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT batch_id, bron_checksum_sha256, status
            FROM bronze.ingestion_batches
            WHERE bron_object_key = %s
            """,
            (object_key,),
        )
        return cursor.fetchone()


def register_or_resume_batch(
    connection, args: argparse.Namespace, checksum: str
) -> tuple[Any, int]:
    existing = existing_batch(connection, args.object_key)
    if existing:
        batch_id, existing_checksum, status = existing
        if existing_checksum != checksum:
            raise RuntimeError(
                "Dit objectpad is al geregistreerd met andere inhoud. "
                "Gebruik een nieuw, datumgebonden objectpad."
            )
        if status == "loaded":
            return batch_id, -1

        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT count(*), COALESCE(max(source_row_number), 1)
                FROM bronze.ndw_intensiteit_snelheid_raw
                WHERE batch_id = %s
                """,
                (batch_id,),
            )
            loaded_count, last_source_row = cursor.fetchone()
            if loaded_count != last_source_row - 1:
                raise RuntimeError(
                    f"Batch {batch_id} bevat geen aaneengesloten bronregels en kan "
                    "niet automatisch worden hervat."
                )
            cursor.execute(
                """
                UPDATE bronze.ingestion_batches
                SET status = 'loading', foutmelding = NULL,
                    aantal_records_gelezen = %s,
                    aantal_records_geladen = %s,
                    updated_at = CURRENT_TIMESTAMP
                WHERE batch_id = %s
                """,
                (loaded_count, loaded_count, batch_id),
            )
        connection.commit()
        return batch_id, last_source_row

    bestandsnaam = args.object_key.rsplit("/", maxsplit=1)[-1]
    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO bronze.ingestion_batches (
                aanvraag_id, exportnaam, bron_object_key, bron_bestandsnaam,
                bron_checksum_sha256, bron_periode_van, bron_periode_tot,
                aggregatieperiode, aggregatievariant,
                meetcompleetheid_meegenomen, aantal_records_gelezen,
                aantal_records_geladen, status
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 0, 0, 'loading')
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
            ),
        )
        batch_id = cursor.fetchone()[0]
    connection.commit()
    return batch_id, 1


def write_batch(connection, batch_id, records: list[tuple[Any, int, str]]) -> None:
    with connection.cursor() as cursor:
        execute_values(
            cursor,
            """
            INSERT INTO bronze.ndw_intensiteit_snelheid_raw (
                batch_id, source_row_number, source_payload
            ) VALUES %s
            """,
            records,
            template="(%s, %s, %s::jsonb)",
            page_size=len(records),
        )
        loaded_count = records[-1][1] - 1
        cursor.execute(
            """
            UPDATE bronze.ingestion_batches
            SET aantal_records_gelezen = %s, aantal_records_geladen = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE batch_id = %s
            """,
            (loaded_count, loaded_count, batch_id),
        )
    connection.commit()


def mark_failed(connection, batch_id, error: Exception) -> None:
    connection.rollback()
    with connection.cursor() as cursor:
        cursor.execute(
            """
            UPDATE bronze.ingestion_batches
            SET status = 'failed', foutmelding = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE batch_id = %s
            """,
            (str(error)[:10_000], batch_id),
        )
    connection.commit()


def ingest(args: argparse.Namespace) -> str:
    started_at = time.monotonic()
    client = minio_client()
    print(f"Checksum berekenen voor s3://{args.bucket}/{args.object_key} ...", flush=True)
    checksum, object_size = object_checksum(client, args.bucket, args.object_key)
    print(
        f"Object gecontroleerd: {object_size:,} bytes; SHA-256 {checksum}.",
        flush=True,
    )

    connection = database_connection()
    batch_id = None
    text_stream = None
    try:
        batch_id, resume_after = register_or_resume_batch(connection, args, checksum)
        if resume_after == -1:
            return f"Batch {batch_id} was al succesvol geladen; geen actie uitgevoerd."
        if resume_after > 1:
            print(
                f"Batch {batch_id} hervatten na bronregel {resume_after:,}.", flush=True
            )

        fieldnames, rows, text_stream = csv_rows(
            client, args.bucket, args.object_key, args.delimiter
        )
        records: list[tuple[Any, int, str]] = []
        total_rows = 0
        last_progress = 0

        for source_row_number, row in rows:
            total_rows = source_row_number - 1
            if source_row_number <= resume_after:
                continue
            records.append(
                (
                    batch_id,
                    source_row_number,
                    json.dumps(row, ensure_ascii=False, separators=(",", ":")),
                )
            )
            if len(records) >= args.batch_size:
                write_batch(connection, batch_id, records)
                records.clear()
            if total_rows - last_progress >= args.progress_every:
                elapsed = time.monotonic() - started_at
                print(
                    f"Voortgang: {total_rows:,} records gelezen "
                    f"({total_rows / max(elapsed, 0.001):,.0f} records/s).",
                    flush=True,
                )
                last_progress = total_rows

        if total_rows == 0:
            raise ValueError("CSV bevat geen datarijen.")
        if records:
            write_batch(connection, batch_id, records)

        with connection.cursor() as cursor:
            cursor.execute(
                """
                UPDATE bronze.ingestion_batches
                SET status = 'loaded', aantal_records_gelezen = %s,
                    aantal_records_geladen = %s, foutmelding = NULL,
                    updated_at = CURRENT_TIMESTAMP
                WHERE batch_id = %s
                """,
                (total_rows, total_rows, batch_id),
            )
        connection.commit()
    except Exception as error:
        if batch_id is not None:
            mark_failed(connection, batch_id, error)
        raise
    finally:
        if text_stream is not None:
            text_stream.close()
        connection.close()

    elapsed = time.monotonic() - started_at
    return (
        f"Batch {batch_id} geladen: {total_rows:,} rijen uit "
        f"s3://{args.bucket}/{args.object_key}; kolommen: {len(fieldnames)}; "
        f"doorlooptijd: {elapsed:.1f} seconden."
    )


if __name__ == "__main__":
    try:
        csv.field_size_limit(sys.maxsize)
        print(ingest(arguments()))
    except Exception as error:
        print(f"Ingestie mislukt: {error}", file=sys.stderr)
        sys.exit(1)
