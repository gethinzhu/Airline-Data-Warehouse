# ETL Report Section

## ETL Process Design and Implementation

### 1. Overview

The ETL process in this project was performed once locally in Python and the cleaned outputs were reused in both PostgreSQL and Databricks. This approach is consistent with the project announcement, which states that the data only needs to be cleaned and transformed once and can then be loaded into both platforms. The ETL workflow followed the standard `Extract -> Transform -> Load -> Validate` sequence.

The main purpose of the ETL pipeline was to integrate the Airline dataset with four supporting datasets (`airports.csv`, `countries.csv`, `regions.csv`, and `navaids.csv`) while preserving the grain of the warehouse. The final warehouse grain remained **one row per passenger-flight record**.

### 2. Source Datasets

Five raw CSV files were used as ETL inputs:

- `Airline Dataset Updated.csv`
- `airports.csv`
- `countries.csv`
- `regions.csv`
- `navaids.csv`

The Airline dataset was treated as the main fact source. The remaining four datasets were used to enrich airport, geography, and navigation-aid related information.

### 3. Extract Phase

In the extract phase, all five raw CSV files were read using Python's built-in CSV module. UTF-8 with BOM handling was applied during file reading to avoid encoding issues in both English and Chinese Windows environments. No records were removed during extraction.

The raw row counts were:

- Airline: 98,619 rows
- Airports: 84,536 rows
- Countries: 249 rows
- Regions: 3,942 rows
- Navaids: 11,010 rows

### 4. Transform Phase

The transformation phase was the most important part of the ETL pipeline. It involved field standardisation, data quality correction, attribute derivation, dataset integration, and dimensional output generation.

#### 4.1 Main data quality correction: `Arrival Airport`

A major data quality issue identified in the project brief is that `Arrival Airport` does **not** represent a true destination airport. Instead, it stores the IATA code of the same airport already described by `Airport Name`. This indicates an ETL transformation error in the original dataset.

Two strategies were possible:

1. Delete the field entirely.
2. Retain the field but rename it to reflect its true meaning.

This project adopted the second strategy. Therefore:

- `Arrival Airport` was retained
- it was reinterpreted as `departure_airport_code`
- it was used as the main key to link the Airline dataset to `airports.csv`

This decision preserved useful airport code information while making the semantics of the field consistent with the project specification.

#### 4.2 Standardisation of main Airline attributes

The Airline dataset was cleaned as follows:

- whitespace was removed from text attributes
- categorical codes were standardised to upper case where appropriate
- `Flight Status` values were normalised to three categories only:
  - `On Time`
  - `Delayed`
  - `Cancelled`
- `Gender` values were normalised to `Male` and `Female`
- `Age` was converted into an integer and mapped into `age_group`
- `Departure Date` was parsed into ISO date format and decomposed into:
  - `month`
  - `quarter`
  - `year`

The age grouping logic used was:

- `0-17`
- `18-25`
- `26-35`
- `36-45`
- `46-60`
- `60+`
- `Unknown`

#### 4.3 Cleaning of supporting datasets

The supporting datasets were cleaned before integration.

For `airports.csv`, the ETL retained and standardised the following key attributes:

- `ident`
- `type`
- `name`
- `continent`
- `iso_country`
- `iso_region`
- `municipality`
- `scheduled_service`
- `iata_code`

For `countries.csv`, the ETL standardised:

- country code
- country name
- continent code and continent name

For `regions.csv`, the ETL standardised:

- region code
- region name
- linked country code
- continent code and continent name

For `navaids.csv`, the ETL standardised:

- `id`
- `ident`
- `type`
- `usageType`
- `power`
- `associated_airport`

#### 4.4 Airport-level navigation-aid aggregation

The `navaids.csv` dataset was **not** joined directly to the fact-level Airline data. This was an important modelling choice, because one airport may be associated with multiple navaids. If the raw navaid rows had been joined directly to passenger-flight records, the fact table would have been duplicated and the warehouse grain would have been broken.

To avoid this problem, `navaids.csv` was first aggregated to airport level using `associated_airport`. The following derived airport-level attributes were created:

- `has_navaid`
- `navaid_count`
- `navaid_count_bucket`
- `navaid_type_group`
- `dominant_usage_type`
- `max_power`

The `navaid_count_bucket` values were defined as:

- `0`
- `1`
- `2-3`
- `4+`

The `navaid_type_group` values were defined as:

- `No Navaid`
- `NDB Family`
- `Radio Nav`
- `Mixed`

This aggregated navaid profile was then attached to the airport dimension rather than to the fact table.

### 5. Dataset Integration Logic

The ETL integration path was:

1. `Airline.departure_airport_code -> airports.iata_code`
2. `airports.iso_region -> regions.code`
3. `airports.iso_country -> countries.code`
4. `airports.ident -> navaids.associated_airport`

This means that `airports.csv` served as the core bridge dataset connecting the Airline records to both geography hierarchies and navigation-aid information.

The integration statistics were:

- Airport IATA matches: 92,807
- Airport IATA unmatched: 5,812
- Region matches: 92,807
- Country matches: 98,619
- Rows with navaid profile: 40,965

For records that could not be fully matched, the ETL assigned default values such as:

- `Unknown Airport`
- `Unknown Region`
- `Unknown Country`
- `No Navaid`

This approach was chosen in order to preserve the main dataset and minimise row loss.

### 6. Row Preservation and ETL Compliance

The project brief states that the ETL process should not remove more than 5% of rows from the main Airline dataset. In this implementation, the ETL preserved the entire main dataset:

- Raw Airline rows: 98,619
- Cleaned Airline rows: 98,619
- Rows dropped from the main dataset: 0

Therefore, the ETL process fully satisfied the row-retention requirement.

### 7. Load Phase

After transformation and integration, the ETL process wrote two categories of outputs:

#### 7.1 Staging outputs

The following staging files were generated:

- `stg_airline.csv`
- `stg_airports.csv`
- `stg_countries.csv`
- `stg_regions.csv`
- `stg_navaids.csv`
- `stg_navaid_profile_by_airport.csv`
- `cleaned_flight_records.csv`

These files were used for validation, traceability, and debugging.

#### 7.2 Warehouse-ready outputs

The ETL then generated the final warehouse-ready tables:

- `dim_date.csv`
- `dim_country.csv`
- `dim_region.csv`
- `dim_airport.csv`
- `dim_passenger.csv`
- `dim_flight_status.csv`
- `fact_passenger_flight.csv`

The dimensional model preserved the star-schema design and kept the fact grain at passenger-flight record level.

### 8. Validate Phase

The ETL validation focused on four aspects:

1. raw row counts versus cleaned row counts
2. join success rates across airport, region, country, and navaid profile
3. preservation of the Airline dataset row count
4. successful generation of final warehouse-ready tables

The ETL summary file confirmed:

- 0 rows were dropped from the Airline dataset
- 4,562 airport-level navaid profiles were created
- 7,375 navaid rows had an associated airport
- 3,635 navaid rows did not have an associated airport and therefore could not contribute to airport-level navigation-aid profiling

### 9. ETL Rationale

The ETL design was driven by three main principles:

1. **semantic correction**: correcting the meaning of `Arrival Airport`
2. **grain preservation**: avoiding direct many-to-one joins from `navaids.csv` into the fact table
3. **row retention**: preserving the Airline dataset by assigning `Unknown` or `No Navaid` values instead of dropping unmatched records

This made the warehouse more coherent and ensured that all five business questions could be answered from the same dimensional structure.

### 10. Conclusion

Overall, the ETL process successfully transformed five heterogeneous raw datasets into a coherent dimensional warehouse structure suitable for both PostgreSQL and Databricks. It corrected the major known data quality issue in the Airline dataset, preserved all main fact rows, integrated geography and navigation-aid information, and produced both staging outputs and final warehouse-ready dimension and fact tables. This ETL process therefore provides a consistent and defensible foundation for the subsequent SQL analysis, cube construction, visualisation, and association rule mining tasks.
