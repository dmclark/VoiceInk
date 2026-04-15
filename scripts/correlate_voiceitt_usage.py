#!/usr/bin/env python3
"""
Correlate Voiceitt API usage data (from developer.voiceitt.com/dashboard/usage)
with local VoiceInk transcription history (from SwiftData/SQLite).

Usage:
    python3 scripts/correlate_voiceitt_usage.py <voiceitt_usage.csv>

The Voiceitt usage CSV should have at least columns for timestamp/date and
request count. The script will auto-detect common column name patterns.

If your exported CSV has different columns, edit VOICEITT_DATE_COL and
VOICEITT_COUNT_COL below.
"""

import argparse
import csv
import os
import sqlite3
import sys
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

# ── Configuration ────────────────────────────────────────────────────────────
# Adjust these if your Voiceitt CSV uses different column headers.
# The script tries several common names automatically.
VOICEITT_DATE_CANDIDATES = ["date", "time", "timestamp", "hour", "datetime", "period"]
VOICEITT_COUNT_CANDIDATES = ["count", "requests", "calls", "usage", "api_calls", "total"]

SWIFTDATA_DB = os.path.expanduser(
    "~/Library/Application Support/com.prakashjoshipax.VoiceInk/default.store"
)
# Core Data epoch: 2001-01-01 00:00:00 UTC
CORE_DATA_EPOCH = datetime(2001, 1, 1)


def find_column(headers: list[str], candidates: list[str]) -> str | None:
    """Find the first header that matches any candidate (case-insensitive)."""
    lower_headers = {h.lower().strip(): h for h in headers}
    for c in candidates:
        if c in lower_headers:
            return lower_headers[c]
    # Partial match fallback
    for c in candidates:
        for lh, orig in lower_headers.items():
            if c in lh:
                return orig
    return None


def parse_voiceitt_csv(path: str) -> dict[str, int]:
    """
    Parse the Voiceitt usage CSV and return {hour_key: request_count}.
    hour_key format: "YYYY-MM-DD HH:00"
    """
    usage_by_hour: dict[str, int] = {}

    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames or []

        date_col = find_column(headers, VOICEITT_DATE_CANDIDATES)
        count_col = find_column(headers, VOICEITT_COUNT_CANDIDATES)

        if not date_col:
            print(f"❌ Could not find a date column in CSV. Headers: {headers}")
            print(f"   Expected one of: {VOICEITT_DATE_CANDIDATES}")
            sys.exit(1)
        if not count_col:
            print(f"⚠️  No count column found; will count rows as 1 request each.")
            print(f"   Headers: {headers}")

        print(f"📄 Using columns: date='{date_col}', count='{count_col or '(1 per row)'}'")

        for row in reader:
            raw_date = row[date_col].strip()
            dt = parse_flexible_date(raw_date)
            if dt is None:
                continue
            hour_key = dt.strftime("%Y-%m-%d %H:00")
            count = int(row[count_col]) if count_col else 1
            usage_by_hour[hour_key] = usage_by_hour.get(hour_key, 0) + count

    return usage_by_hour


def parse_flexible_date(s: str) -> datetime | None:
    """Try several datetime formats."""
    formats = [
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M:%SZ",
        "%Y-%m-%dT%H:%M:%S.%f",
        "%Y-%m-%dT%H:%M:%S.%fZ",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d %H:00",
        "%Y-%m-%d",
        "%m/%d/%Y %H:%M:%S",
        "%m/%d/%Y %H:%M",
        "%m/%d/%Y",
        "%d/%m/%Y %H:%M:%S",
        "%d/%m/%Y",
    ]
    for fmt in formats:
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    # Try Unix timestamp (seconds)
    try:
        ts = float(s)
        return datetime.fromtimestamp(ts)
    except (ValueError, OSError):
        pass
    return None


def load_transcriptions(db_path: str = SWIFTDATA_DB) -> list[dict]:
    """Load Voiceitt transcriptions from the local SwiftData SQLite DB."""
    if not os.path.exists(db_path):
        print(f"❌ SwiftData DB not found at: {db_path}")
        sys.exit(1)

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.execute(
        """
        SELECT
            ZTIMESTAMP,
            ZDURATION,
            ZTRANSCRIPTIONDURATION,
            ZTRANSCRIPTIONMODELNAME,
            ZTRANSCRIPTIONSTATUS,
            ZTEXT,
            ZENHANCEDTEXT,
            ZPOWERMODENAME
        FROM ZTRANSCRIPTION
        WHERE ZTRANSCRIPTIONMODELNAME LIKE '%oiceitt%'
        ORDER BY ZTIMESTAMP
        """
    )
    rows = []
    for r in cursor:
        ts = r["ZTIMESTAMP"]
        if ts is None:
            continue
        dt = CORE_DATA_EPOCH + timedelta(seconds=ts)
        rows.append(
            {
                "datetime": dt,
                "hour_key": dt.strftime("%Y-%m-%d %H:00"),
                "duration_s": r["ZDURATION"] or 0,
                "transcription_duration_s": r["ZTRANSCRIPTIONDURATION"] or 0,
                "model": r["ZTRANSCRIPTIONMODELNAME"] or "",
                "status": r["ZTRANSCRIPTIONSTATUS"] or "",
                "text": (r["ZTEXT"] or "")[:80],
                "enhanced_text": (r["ZENHANCEDTEXT"] or "")[:80],
                "power_mode": r["ZPOWERMODENAME"] or "",
            }
        )
    conn.close()
    return rows


def correlate(
    voiceitt_usage: dict[str, int], transcriptions: list[dict]
) -> list[dict]:
    """Merge Voiceitt API usage and local transcriptions by hour."""
    # Group local transcriptions by hour
    local_by_hour: dict[str, list[dict]] = defaultdict(list)
    for t in transcriptions:
        local_by_hour[t["hour_key"]].append(t)

    all_hours = sorted(set(list(voiceitt_usage.keys()) + list(local_by_hour.keys())))

    results = []
    for hour in all_hours:
        api_count = voiceitt_usage.get(hour, 0)
        local_txns = local_by_hour.get(hour, [])
        local_count = len(local_txns)
        avg_duration = (
            sum(t["duration_s"] for t in local_txns) / local_count
            if local_count
            else 0
        )
        avg_transcription_time = (
            sum(t["transcription_duration_s"] for t in local_txns) / local_count
            if local_count
            else 0
        )

        results.append(
            {
                "hour": hour,
                "api_requests": api_count,
                "local_transcriptions": local_count,
                "delta": api_count - local_count,
                "avg_recording_duration_s": round(avg_duration, 1),
                "avg_transcription_time_s": round(avg_transcription_time, 1),
            }
        )

    return results


def print_report(correlated: list[dict], transcriptions: list[dict]):
    """Print a formatted correlation report."""
    print("\n" + "=" * 90)
    print("VOICEITT API USAGE vs LOCAL TRANSCRIPTION CORRELATION REPORT")
    print("=" * 90)

    # Summary
    total_api = sum(r["api_requests"] for r in correlated)
    total_local = sum(r["local_transcriptions"] for r in correlated)
    print(f"\n📊 Summary:")
    print(f"   Total API requests (Voiceitt dashboard):  {total_api}")
    print(f"   Total local Voiceitt transcriptions:       {total_local}")
    print(f"   Delta (API - local):                       {total_api - total_local}")
    if total_local:
        avg_dur = sum(t["duration_s"] for t in transcriptions) / total_local
        avg_txn = sum(t["transcription_duration_s"] for t in transcriptions) / total_local
        print(f"   Avg recording duration:                    {avg_dur:.1f}s")
        print(f"   Avg transcription time:                    {avg_txn:.1f}s")

    # Hourly table
    print(f"\n{'Hour':<20} {'API Reqs':>10} {'Local Txns':>12} {'Delta':>8} {'Avg Rec(s)':>11} {'Avg Txn(s)':>11}")
    print("-" * 90)

    for r in correlated:
        flag = " ⚠️" if r["delta"] != 0 else ""
        print(
            f"{r['hour']:<20} {r['api_requests']:>10} {r['local_transcriptions']:>12} "
            f"{r['delta']:>8} {r['avg_recording_duration_s']:>11.1f} "
            f"{r['avg_transcription_time_s']:>11.1f}{flag}"
        )

    # Show mismatched hours
    mismatches = [r for r in correlated if r["delta"] != 0]
    if mismatches:
        print(f"\n⚠️  {len(mismatches)} hour(s) with mismatched counts (API ≠ local).")
        print("   Possible causes: failed requests, retries, streaming reconnects,")
        print("   or requests from other clients using the same API key.")

    # Detail listing
    print(f"\n{'─' * 90}")
    print("DETAILED LOCAL TRANSCRIPTIONS (Voiceitt only)")
    print(f"{'─' * 90}")
    print(f"{'Time':<22} {'Dur(s)':>7} {'Txn(s)':>7} {'Status':<12} {'Text'}")
    print("-" * 90)
    for t in transcriptions:
        time_str = t["datetime"].strftime("%Y-%m-%d %H:%M:%S")
        text_preview = t["text"][:50].replace("\n", " ")
        print(
            f"{time_str:<22} {t['duration_s']:>7.1f} {t['transcription_duration_s']:>7.1f} "
            f"{t['status']:<12} {text_preview}"
        )


def export_csv(correlated: list[dict], output_path: str):
    """Write correlated data to CSV for further analysis."""
    with open(output_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=correlated[0].keys())
        writer.writeheader()
        writer.writerows(correlated)
    print(f"\n📁 Correlated data exported to: {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Correlate Voiceitt API usage with local VoiceInk transcription history."
    )
    parser.add_argument(
        "voiceitt_csv",
        help="Path to Voiceitt usage CSV exported from developer.voiceitt.com/dashboard/usage",
    )
    parser.add_argument(
        "-o", "--output",
        default=os.path.expanduser("~/Documents/voiceitt-correlation.csv"),
        help="Output CSV path (default: ~/Documents/voiceitt-correlation.csv)",
    )
    parser.add_argument(
        "--db",
        default=SWIFTDATA_DB,
        help="Path to VoiceInk SwiftData store (default: standard location)",
    )
    parser.add_argument(
        "--local-only",
        action="store_true",
        help="Skip Voiceitt CSV and just dump local transcription data",
    )
    args = parser.parse_args()

    db_path = args.db

    print("🔍 Loading local VoiceInk transcriptions...")
    transcriptions = load_transcriptions(db_path)
    print(f"   Found {len(transcriptions)} Voiceitt transcriptions in local DB.")

    if args.local_only:
        print_report([], transcriptions)
        return

    print(f"\n📄 Loading Voiceitt API usage from: {args.voiceitt_csv}")
    voiceitt_usage = parse_voiceitt_csv(args.voiceitt_csv)
    print(f"   Found {sum(voiceitt_usage.values())} API requests across {len(voiceitt_usage)} hours.")

    print("\n🔗 Correlating data by hour...")
    correlated = correlate(voiceitt_usage, transcriptions)

    print_report(correlated, transcriptions)
    export_csv(correlated, args.output)


if __name__ == "__main__":
    main()
