from __future__ import annotations

import csv
import json
import re
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
INPUT_DIR = PROJECT_ROOT / "Datasets CSV"
OUTPUT_DIR = PROJECT_ROOT / "ETL" / "output"
STAGING_DIR = OUTPUT_DIR / "staging"
WAREHOUSE_DIR = OUTPUT_DIR / "warehouse"


CONTINENT_MAP = {
    "AF": "Africa",
    "AN": "Antarctica",
    "AS": "Asia",
    "EU": "Europe",
    "NA": "North America",
    "NAM": "North America",
    "OC": "Oceania",
    "OCE": "Oceania",
    "SA": "South America",
    "SAM": "South America",
}

STATUS_MAP = {
    "on time": "On Time",
    "ontime": "On Time",
    "delayed": "Delayed",
    "cancelled": "Cancelled",
    "canceled": "Cancelled",
}

GENDER_MAP = {
    "male": "Male",
    "female": "Female",
}

NDB_TYPES = {"NDB", "NDB-DME"}
RADIO_NAV_TYPES = {"VOR", "VOR-DME", "VORTAC", "TACAN", "DME"}
POWER_RANK = {"LOW": 1, "MEDIUM": 2, "HIGH": 3, "UNKNOWN": 0}


def normalize_text(value: Any) -> str:
    if value is None:
        return ""
    return re.sub(r"\s+", " ", str(value)).strip()


def normalize_code(value: Any) -> str:
    return normalize_text(value).upper()


def continent_name_from_code(code: Any) -> str:
    normalized = normalize_code(code)
    return CONTINENT_MAP.get(normalized, "Unknown")


def normalize_status(value: Any) -> str:
    normalized = normalize_text(value).lower()
    return STATUS_MAP.get(normalized, normalize_text(value) or "Unknown")


def normalize_gender(value: Any) -> str:
    normalized = normalize_text(value).lower()
    return GENDER_MAP.get(normalized, normalize_text(value).title() or "Unknown")


def safe_int(value: Any, minimum: int | None = None, maximum: int | None = None) -> int | None:
    text = normalize_text(value)
    if not text:
        return None
    try:
        parsed = int(float(text))
    except ValueError:
        return None
    if minimum is not None and parsed < minimum:
        return None
    if maximum is not None and parsed > maximum:
        return None
    return parsed


def age_group(age: int | None) -> str:
    if age is None:
        return "Unknown"
    if age < 18:
        return "0-17"
    if age <= 25:
        return "18-25"
    if age <= 35:
        return "26-35"
    if age <= 45:
        return "36-45"
    if age <= 60:
        return "46-60"
    return "60+"


def parse_project_date(raw_value: Any) -> tuple[str, int | None, str, int | None]:
    raw = normalize_text(raw_value)
    if not raw:
        return "", None, "", None

    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", raw):
        dt = datetime.strptime(raw, "%Y-%m-%d")
        return dt.date().isoformat(), dt.month, f"Q{((dt.month - 1) // 3) + 1}", dt.year

    match = re.fullmatch(r"(\d{1,2})([-/])(\d{1,2})\2(\d{4})", raw)
    if match:
        first = int(match.group(1))
        second = int(match.group(3))
        year = int(match.group(4))

        # Kaggle-style dates in this dataset are primarily month-day-year.
        # If the first token exceeds 12, we switch to day-month-year.
        if first > 12 and second <= 12:
            day = first
            month = second
        else:
            month = first
            day = second

        dt = datetime(year, month, day)
        return dt.date().isoformat(), dt.month, f"Q{((dt.month - 1) // 3) + 1}", dt.year

    for fmt in ("%m/%d/%Y", "%m-%d-%Y", "%d-%m-%Y", "%d/%m/%Y"):
        try:
            dt = datetime.strptime(raw, fmt)
            return dt.date().isoformat(), dt.month, f"Q{((dt.month - 1) // 3) + 1}", dt.year
        except ValueError:
            continue

    raise ValueError(f"Unsupported date format: {raw}")


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", errors="replace", newline="") as fh:
        return list(csv.DictReader(fh))


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})


def clean_airports(rows: list[dict[str, str]]) -> list[dict[str, Any]]:
    cleaned: list[dict[str, Any]] = []
    for row in rows:
        cleaned.append(
            {
                "airport_ident": normalize_code(row.get("ident")),
                "airport_type": normalize_text(row.get("type")) or "Unknown",
                "airport_name_ref": normalize_text(row.get("name")),
                "continent_code": normalize_code(row.get("continent")),
                "continent_name": continent_name_from_code(row.get("continent")),
                "country_code": normalize_code(row.get("iso_country")),
                "region_code": normalize_code(row.get("iso_region")),
                "municipality": normalize_text(row.get("municipality")) or "Unknown",
                "scheduled_service": normalize_text(row.get("scheduled_service")).lower() or "unknown",
                "iata_code": normalize_code(row.get("iata_code")),
            }
        )
    return cleaned


def clean_countries(rows: list[dict[str, str]]) -> list[dict[str, Any]]:
    cleaned: list[dict[str, Any]] = []
    for row in rows:
        cleaned.append(
            {
                "country_code": normalize_code(row.get("code")),
                "country_name": normalize_text(row.get("name")) or "Unknown Country",
                "continent_code": normalize_code(row.get("continent")),
                "continent_name": continent_name_from_code(row.get("continent")),
            }
        )
    return cleaned


def clean_regions(rows: list[dict[str, str]]) -> list[dict[str, Any]]:
    cleaned: list[dict[str, Any]] = []
    for row in rows:
        cleaned.append(
            {
                "region_code": normalize_code(row.get("code")),
                "region_name": normalize_text(row.get("name")) or "Unknown Region",
                "country_code": normalize_code(row.get("iso_country")),
                "continent_code": normalize_code(row.get("continent")),
                "continent_name": continent_name_from_code(row.get("continent")),
            }
        )
    return cleaned


def clean_navaids(rows: list[dict[str, str]]) -> list[dict[str, Any]]:
    cleaned: list[dict[str, Any]] = []
    for row in rows:
        cleaned.append(
            {
                "navaid_id": normalize_text(row.get("id")),
                "filename": normalize_text(row.get("filename")),
                "ident": normalize_code(row.get("ident")),
                "navaid_name": normalize_text(row.get("name")),
                "navaid_type": normalize_text(row.get("type")).upper(),
                "iso_country": normalize_code(row.get("iso_country")),
                "usage_type": normalize_text(row.get("usageType")).upper() or "UNKNOWN",
                "power": normalize_text(row.get("power")).upper() or "UNKNOWN",
                "associated_airport": normalize_code(row.get("associated_airport")),
            }
        )
    return cleaned


def build_navaid_profiles(cleaned_navaids: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in cleaned_navaids:
        if row["associated_airport"]:
            grouped[row["associated_airport"]].append(row)

    profiles: list[dict[str, Any]] = []
    for airport_ident, items in sorted(grouped.items()):
        types = {item["navaid_type"] for item in items if item["navaid_type"]}
        usage_counter = Counter(item["usage_type"] for item in items if item["usage_type"])
        max_power = "UNKNOWN"
        max_rank = -1
        for item in items:
            power = item["power"] or "UNKNOWN"
            rank = POWER_RANK.get(power, 0)
            if rank > max_rank:
                max_rank = rank
                max_power = power

        if not types:
            navaid_type_group = "No Navaid"
        elif types.issubset(NDB_TYPES):
            navaid_type_group = "NDB Family"
        elif types.issubset(RADIO_NAV_TYPES):
            navaid_type_group = "Radio Nav"
        else:
            navaid_type_group = "Mixed"

        navaid_count = len(items)
        if navaid_count == 1:
            count_bucket = "1"
        elif 2 <= navaid_count <= 3:
            count_bucket = "2-3"
        else:
            count_bucket = "4+"

        profiles.append(
            {
                "airport_ident": airport_ident,
                "has_navaid": "Y",
                "navaid_count": navaid_count,
                "navaid_count_bucket": count_bucket,
                "navaid_type_group": navaid_type_group,
                "dominant_usage_type": usage_counter.most_common(1)[0][0] if usage_counter else "UNKNOWN",
                "max_power": max_power,
            }
        )
    return profiles


def clean_airline_rows(
    rows: list[dict[str, str]],
    airports_by_iata: dict[str, dict[str, Any]],
    regions_by_code: dict[str, dict[str, Any]],
    countries_by_code: dict[str, dict[str, Any]],
    navaid_profiles_by_airport: dict[str, dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    staging_rows: list[dict[str, Any]] = []
    integrated_rows: list[dict[str, Any]] = []

    airport_matches = 0
    region_matches = 0
    country_matches = 0
    navaid_matches = 0

    for row in rows:
        parsed_date, month, quarter, year = parse_project_date(row.get("Departure Date"))
        age = safe_int(row.get("Age"), minimum=0, maximum=120)
        departure_airport_code = normalize_code(row.get("Arrival Airport"))

        staging_row = {
            "passenger_id": normalize_text(row.get("Passenger ID")),
            "first_name": normalize_text(row.get("First Name")),
            "last_name": normalize_text(row.get("Last Name")),
            "gender": normalize_gender(row.get("Gender")),
            "age": age if age is not None else "",
            "age_group": age_group(age),
            "nationality": normalize_text(row.get("Nationality")) or "Unknown",
            "airport_name": normalize_text(row.get("Airport Name")) or "Unknown Airport",
            "airport_country_code": normalize_code(row.get("Airport Country Code")) or "UNKNOWN",
            "country_name": normalize_text(row.get("Country Name")) or "Unknown Country",
            "airport_continent_code": normalize_code(row.get("Airport Continent")) or "UNKNOWN",
            "airport_continent_name": continent_name_from_code(row.get("Airport Continent")),
            "continents": normalize_text(row.get("Continents")),
            "departure_date": parsed_date,
            "month": month if month is not None else "",
            "quarter": quarter,
            "year": year if year is not None else "",
            # Project brief: this is not a true destination airport.
            "departure_airport_code": departure_airport_code,
            "pilot_name": normalize_text(row.get("Pilot Name")),
            "flight_status": normalize_status(row.get("Flight Status")),
        }
        staging_rows.append(staging_row)

        airport = airports_by_iata.get(departure_airport_code)
        if airport:
            airport_matches += 1

        region_code = airport["region_code"] if airport else ""
        region = regions_by_code.get(region_code) if region_code else None
        if region:
            region_matches += 1

        country_code = airport["country_code"] if airport and airport["country_code"] else staging_row["airport_country_code"]
        country = countries_by_code.get(country_code) if country_code else None
        if country:
            country_matches += 1

        airport_ident = airport["airport_ident"] if airport and airport["airport_ident"] else ""
        navaid_profile = navaid_profiles_by_airport.get(airport_ident) if airport_ident else None
        if navaid_profile:
            navaid_matches += 1

        airport_lookup_key = airport_ident or departure_airport_code or staging_row["airport_name"]
        passenger_lookup_key = staging_row["passenger_id"] or f"{staging_row['first_name']}|{staging_row['last_name']}"

        integrated_rows.append(
            {
                "passenger_lookup_key": passenger_lookup_key or "UNKNOWN",
                "airport_lookup_key": airport_lookup_key or "UNKNOWN",
                "flight_status_lookup_key": staging_row["flight_status"] or "Unknown",
                "date_lookup_key": staging_row["departure_date"] or "UNKNOWN",
                "passenger_id": staging_row["passenger_id"],
                "first_name": staging_row["first_name"],
                "last_name": staging_row["last_name"],
                "gender": staging_row["gender"],
                "age": staging_row["age"],
                "age_group": staging_row["age_group"],
                "nationality": staging_row["nationality"],
                "full_date": staging_row["departure_date"],
                "month": staging_row["month"],
                "quarter": staging_row["quarter"],
                "year": staging_row["year"],
                "flight_status": staging_row["flight_status"],
                "airport_ident": airport_ident or "UNKNOWN",
                "departure_airport_code": staging_row["departure_airport_code"],
                "airport_name": airport["airport_name_ref"] if airport and airport["airport_name_ref"] else staging_row["airport_name"],
                "airport_type": airport["airport_type"] if airport else "Unknown",
                "municipality": airport["municipality"] if airport else "Unknown",
                "scheduled_service": airport["scheduled_service"] if airport else "unknown",
                "region_code": region["region_code"] if region else "UNKNOWN",
                "region_name": region["region_name"] if region else "Unknown Region",
                "country_code": country_code or "UNKNOWN",
                "country_name": country["country_name"] if country else staging_row["country_name"],
                "continent_name": (
                    region["continent_name"]
                    if region
                    else country["continent_name"]
                    if country
                    else airport["continent_name"]
                    if airport
                    else staging_row["airport_continent_name"]
                ),
                "has_navaid": navaid_profile["has_navaid"] if navaid_profile else "N",
                "navaid_count": navaid_profile["navaid_count"] if navaid_profile else 0,
                "navaid_count_bucket": navaid_profile["navaid_count_bucket"] if navaid_profile else "0",
                "navaid_type_group": navaid_profile["navaid_type_group"] if navaid_profile else "No Navaid",
                "dominant_usage_type": navaid_profile["dominant_usage_type"] if navaid_profile else "UNKNOWN",
                "max_power": navaid_profile["max_power"] if navaid_profile else "UNKNOWN",
                "pilot_name": staging_row["pilot_name"],
            }
        )

    stats = {
        "airport_iata_matches": airport_matches,
        "airport_iata_unmatched": len(rows) - airport_matches,
        "region_matches": region_matches,
        "country_matches": country_matches,
        "rows_with_navaid_profile": navaid_matches,
    }
    return staging_rows, integrated_rows, stats


def build_dim_date(integrated_rows: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, int]]:
    rows = [{"date_key": 0, "full_date": "", "day_of_month": 0, "month": 0, "month_name": "Unknown", "quarter": "", "year": 0}]
    lookup = {"UNKNOWN": 0, "": 0}
    next_key = 1

    for row in integrated_rows:
        full_date = row["full_date"]
        if not full_date or full_date in lookup:
            continue
        dt = datetime.strptime(full_date, "%Y-%m-%d")
        lookup[full_date] = next_key
        rows.append(
            {
                "date_key": next_key,
                "full_date": full_date,
                "day_of_month": dt.day,
                "month": dt.month,
                "month_name": dt.strftime("%B"),
                "quarter": f"Q{((dt.month - 1) // 3) + 1}",
                "year": dt.year,
            }
        )
        next_key += 1
    return rows, lookup


def build_simple_dimension(
    integrated_rows: list[dict[str, Any]],
    lookup_field: str,
    output_fields: list[str],
    key_name: str,
    unknown_row: dict[str, Any],
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    rows = [unknown_row]
    lookup = {"UNKNOWN": 0, "": 0}
    next_key = 1

    for row in integrated_rows:
        lookup_value = row[lookup_field] or "UNKNOWN"
        if lookup_value in lookup:
            continue
        lookup[lookup_value] = next_key
        dim_row = {key_name: next_key}
        for field in output_fields:
            dim_row[field] = row[field]
        rows.append(dim_row)
        next_key += 1
    return rows, lookup


def build_fact_table(
    integrated_rows: list[dict[str, Any]],
    date_lookup: dict[str, int],
    country_lookup: dict[str, int],
    region_lookup: dict[str, int],
    airport_lookup: dict[str, int],
    passenger_lookup: dict[str, int],
    status_lookup: dict[str, int],
) -> list[dict[str, Any]]:
    fact_rows: list[dict[str, Any]] = []
    for idx, row in enumerate(integrated_rows, start=1):
        status = row["flight_status"]
        fact_rows.append(
            {
                "fact_id": idx,
                "date_key": date_lookup.get(row["date_lookup_key"], 0),
                "airport_key": airport_lookup.get(row["airport_lookup_key"], 0),
                "region_key": region_lookup.get(row["region_code"], 0),
                "country_key": country_lookup.get(row["country_code"], 0),
                "passenger_key": passenger_lookup.get(row["passenger_lookup_key"], 0),
                "flight_status_key": status_lookup.get(row["flight_status_lookup_key"], 0),
                "flight_record_count": 1,
                "delayed_flag": 1 if status == "Delayed" else 0,
                "cancelled_flag": 1 if status == "Cancelled" else 0,
                "ontime_flag": 1 if status == "On Time" else 0,
            }
        )
    return fact_rows


def main() -> None:
    STAGING_DIR.mkdir(parents=True, exist_ok=True)
    WAREHOUSE_DIR.mkdir(parents=True, exist_ok=True)

    airline_raw = read_csv_rows(INPUT_DIR / "Airline Dataset Updated.csv")
    airports_raw = read_csv_rows(INPUT_DIR / "airports.csv")
    countries_raw = read_csv_rows(INPUT_DIR / "countries.csv")
    regions_raw = read_csv_rows(INPUT_DIR / "regions.csv")
    navaids_raw = read_csv_rows(INPUT_DIR / "navaids.csv")

    cleaned_airports = clean_airports(airports_raw)
    cleaned_countries = clean_countries(countries_raw)
    cleaned_regions = clean_regions(regions_raw)
    cleaned_navaids = clean_navaids(navaids_raw)

    airports_by_iata = {row["iata_code"]: row for row in cleaned_airports if row["iata_code"]}
    regions_by_code = {row["region_code"]: row for row in cleaned_regions if row["region_code"]}
    countries_by_code = {row["country_code"]: row for row in cleaned_countries if row["country_code"]}

    navaid_profiles = build_navaid_profiles(cleaned_navaids)
    navaid_profiles_by_airport = {row["airport_ident"]: row for row in navaid_profiles}

    staging_airline, integrated_rows, join_stats = clean_airline_rows(
        airline_raw,
        airports_by_iata,
        regions_by_code,
        countries_by_code,
        navaid_profiles_by_airport,
    )

    dim_date, date_lookup = build_dim_date(integrated_rows)
    dim_country, country_lookup = build_simple_dimension(
        integrated_rows,
        lookup_field="country_code",
        output_fields=["country_code", "country_name", "continent_name"],
        key_name="country_key",
        unknown_row={
            "country_key": 0,
            "country_code": "UNKNOWN",
            "country_name": "Unknown Country",
            "continent_name": "Unknown",
        },
    )
    dim_region, region_lookup = build_simple_dimension(
        integrated_rows,
        lookup_field="region_code",
        output_fields=["region_code", "region_name", "country_code", "continent_name"],
        key_name="region_key",
        unknown_row={
            "region_key": 0,
            "region_code": "UNKNOWN",
            "region_name": "Unknown Region",
            "country_code": "UNKNOWN",
            "continent_name": "Unknown",
        },
    )
    dim_airport, airport_lookup = build_simple_dimension(
        integrated_rows,
        lookup_field="airport_lookup_key",
        output_fields=[
            "airport_ident",
            "airport_name",
            "departure_airport_code",
            "airport_type",
            "municipality",
            "scheduled_service",
            "region_code",
            "country_code",
            "has_navaid",
            "navaid_count",
            "navaid_count_bucket",
            "navaid_type_group",
            "dominant_usage_type",
            "max_power",
        ],
        key_name="airport_key",
        unknown_row={
            "airport_key": 0,
            "airport_ident": "UNKNOWN",
            "airport_name": "Unknown Airport",
            "departure_airport_code": "",
            "airport_type": "Unknown",
            "municipality": "Unknown",
            "scheduled_service": "unknown",
            "region_code": "UNKNOWN",
            "country_code": "UNKNOWN",
            "has_navaid": "N",
            "navaid_count": 0,
            "navaid_count_bucket": "0",
            "navaid_type_group": "No Navaid",
            "dominant_usage_type": "UNKNOWN",
            "max_power": "UNKNOWN",
        },
    )
    dim_passenger, passenger_lookup = build_simple_dimension(
        integrated_rows,
        lookup_field="passenger_lookup_key",
        output_fields=["passenger_id", "first_name", "last_name", "gender", "age", "age_group", "nationality"],
        key_name="passenger_key",
        unknown_row={
            "passenger_key": 0,
            "passenger_id": "",
            "first_name": "",
            "last_name": "",
            "gender": "Unknown",
            "age": "",
            "age_group": "Unknown",
            "nationality": "Unknown",
        },
    )
    dim_flight_status, status_lookup = build_simple_dimension(
        integrated_rows,
        lookup_field="flight_status_lookup_key",
        output_fields=["flight_status"],
        key_name="flight_status_key",
        unknown_row={
            "flight_status_key": 0,
            "flight_status": "Unknown",
        },
    )
    fact_rows = build_fact_table(
        integrated_rows,
        date_lookup,
        country_lookup,
        region_lookup,
        airport_lookup,
        passenger_lookup,
        status_lookup,
    )

    write_csv(
        STAGING_DIR / "stg_airline.csv",
        staging_airline,
        [
            "passenger_id",
            "first_name",
            "last_name",
            "gender",
            "age",
            "age_group",
            "nationality",
            "airport_name",
            "airport_country_code",
            "country_name",
            "airport_continent_code",
            "airport_continent_name",
            "continents",
            "departure_date",
            "month",
            "quarter",
            "year",
            "departure_airport_code",
            "pilot_name",
            "flight_status",
        ],
    )
    write_csv(
        STAGING_DIR / "stg_airports.csv",
        cleaned_airports,
        [
            "airport_ident",
            "airport_type",
            "airport_name_ref",
            "continent_code",
            "continent_name",
            "country_code",
            "region_code",
            "municipality",
            "scheduled_service",
            "iata_code",
        ],
    )
    write_csv(
        STAGING_DIR / "stg_countries.csv",
        cleaned_countries,
        ["country_code", "country_name", "continent_code", "continent_name"],
    )
    write_csv(
        STAGING_DIR / "stg_regions.csv",
        cleaned_regions,
        ["region_code", "region_name", "country_code", "continent_code", "continent_name"],
    )
    write_csv(
        STAGING_DIR / "stg_navaids.csv",
        cleaned_navaids,
        [
            "navaid_id",
            "filename",
            "ident",
            "navaid_name",
            "navaid_type",
            "iso_country",
            "usage_type",
            "power",
            "associated_airport",
        ],
    )
    write_csv(
        STAGING_DIR / "stg_navaid_profile_by_airport.csv",
        navaid_profiles,
        [
            "airport_ident",
            "has_navaid",
            "navaid_count",
            "navaid_count_bucket",
            "navaid_type_group",
            "dominant_usage_type",
            "max_power",
        ],
    )
    write_csv(
        STAGING_DIR / "cleaned_flight_records.csv",
        integrated_rows,
        [
            "passenger_lookup_key",
            "airport_lookup_key",
            "flight_status_lookup_key",
            "date_lookup_key",
            "passenger_id",
            "first_name",
            "last_name",
            "gender",
            "age",
            "age_group",
            "nationality",
            "full_date",
            "month",
            "quarter",
            "year",
            "flight_status",
            "airport_ident",
            "departure_airport_code",
            "airport_name",
            "airport_type",
            "municipality",
            "scheduled_service",
            "region_code",
            "region_name",
            "country_code",
            "country_name",
            "continent_name",
            "has_navaid",
            "navaid_count",
            "navaid_count_bucket",
            "navaid_type_group",
            "dominant_usage_type",
            "max_power",
            "pilot_name",
        ],
    )

    write_csv(
        WAREHOUSE_DIR / "dim_date.csv",
        dim_date,
        ["date_key", "full_date", "day_of_month", "month", "month_name", "quarter", "year"],
    )
    write_csv(
        WAREHOUSE_DIR / "dim_country.csv",
        dim_country,
        ["country_key", "country_code", "country_name", "continent_name"],
    )
    write_csv(
        WAREHOUSE_DIR / "dim_region.csv",
        dim_region,
        ["region_key", "region_code", "region_name", "country_code", "continent_name"],
    )
    write_csv(
        WAREHOUSE_DIR / "dim_airport.csv",
        dim_airport,
        [
            "airport_key",
            "airport_ident",
            "airport_name",
            "departure_airport_code",
            "airport_type",
            "municipality",
            "scheduled_service",
            "region_code",
            "country_code",
            "has_navaid",
            "navaid_count",
            "navaid_count_bucket",
            "navaid_type_group",
            "dominant_usage_type",
            "max_power",
        ],
    )
    write_csv(
        WAREHOUSE_DIR / "dim_passenger.csv",
        dim_passenger,
        ["passenger_key", "passenger_id", "first_name", "last_name", "gender", "age", "age_group", "nationality"],
    )
    write_csv(
        WAREHOUSE_DIR / "dim_flight_status.csv",
        dim_flight_status,
        ["flight_status_key", "flight_status"],
    )
    write_csv(
        WAREHOUSE_DIR / "fact_passenger_flight.csv",
        fact_rows,
        [
            "fact_id",
            "date_key",
            "airport_key",
            "region_key",
            "country_key",
            "passenger_key",
            "flight_status_key",
            "flight_record_count",
            "delayed_flag",
            "cancelled_flag",
            "ontime_flag",
        ],
    )

    summary = {
        "main_dataset_rows_raw": len(airline_raw),
        "main_dataset_rows_after_cleaning": len(staging_airline),
        "main_dataset_rows_dropped": len(airline_raw) - len(staging_airline),
        "raw_row_counts": {
            "airline": len(airline_raw),
            "airports": len(airports_raw),
            "countries": len(countries_raw),
            "regions": len(regions_raw),
            "navaids": len(navaids_raw),
        },
        "join_stats": join_stats,
        "navaids": {
            "rows_with_associated_airport": sum(1 for row in cleaned_navaids if row["associated_airport"]),
            "rows_without_associated_airport": sum(1 for row in cleaned_navaids if not row["associated_airport"]),
            "airport_profiles_created": len(navaid_profiles),
        },
        "output_files": {
            "staging_dir": str(STAGING_DIR),
            "warehouse_dir": str(WAREHOUSE_DIR),
        },
        "arrival_airport_treatment": {
            "chosen_strategy": "rename",
            "new_column_name": "departure_airport_code",
            "reason": (
                "The project brief identifies 'Arrival Airport' as an ETL transformation error. "
                "It stores the IATA code of the same airport recorded in 'Airport Name', "
                "so it is retained only as the departure airport code."
            ),
        },
    }

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUTPUT_DIR / "etl_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print("ETL finished.")
    print(f"Staging outputs:   {STAGING_DIR}")
    print(f"Warehouse outputs: {WAREHOUSE_DIR}")
    print(f"Summary file:      {OUTPUT_DIR / 'etl_summary.json'}")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
