# Airline Data Warehouse Project Report Draft

> ??????????? Markdown ?????????????????????????

---

## 1. Introduction

Air transportation systems generate large volumes of operational data across airports, countries, regions, time periods, and infrastructure environments. However, raw operational datasets are often difficult to analyse directly because they contain inconsistent semantics, weak dimensional structure, and limited integration across related datasets. The purpose of this project is to design and implement a data warehouse solution that supports multidimensional analysis of airline operational performance using the provided Airline dataset together with additional aviation-related datasets.

This project uses the Airline dataset as the main fact source and integrates four supporting datasets: `airports.csv`, `countries.csv`, `regions.csv`, and `navaids.csv`. A dimensional warehouse was implemented in both PostgreSQL and Databricks. In PostgreSQL, a full warehouse schema and cube-oriented materialized views were built to support multidimensional analysis. In Databricks, the cleaned warehouse-ready data was also loaded for platform comparison. In addition, association rule mining was conducted in Python to identify statistically interesting combinations of operational conditions associated with `Flight Status`.

The overall goal of the project is to build a coherent warehouse design that supports business analysis across time, geography, airport operations, navigation-aid availability, and passenger-related attributes.

---

## 2. Fixed Business Questions

The following five business questions were used as the analytical basis of the project.

1. Which countries and regions have the highest number and proportion of delayed or cancelled flights?
2. How does flight status change across month and quarter within the observed year?
3. Which airports handle the greatest traffic volume, and how do their flight status distributions compare?
4. How does flight status performance vary across airport, region, country, and continent hierarchies with different levels of navigation-aid availability?
5. Which combinations of time, geographic, and passenger related attributes are associated with different flight status outcomes?

These questions were selected because, together, they cover the major analytical dimensions required by the project: time hierarchy, geography hierarchy, airport comparison, external infrastructure enrichment through `navaids.csv`, and passenger attribute analysis.

---

## 3. Datasets Used

### 3.1 Main Dataset

- `Airline Dataset Updated.csv`

This dataset serves as the main source of passenger-flight records and provides the base grain for the warehouse.

### 3.2 Supporting Datasets

- `airports.csv`
- `countries.csv`
- `regions.csv`
- `navaids.csv`

These supporting datasets were used to enrich airport, country, region, continent, and navigation-aid related attributes.

### 3.3 Key Data Quality Issue

According to the project specification, the field `Arrival Airport` in the Airline dataset is not a true destination airport. Instead, it contains the IATA code of the same airport described in `Airport Name`. This is an ETL transformation error in the original data pipeline. In this project, the field was retained and reinterpreted as `departure_airport_code`, because it is useful as a link to `airports.csv`.

---

## 4. Dimensional Design

### 4.1 Kimball Four-Step Design

The warehouse design followed Kimball's four-step dimensional modelling process.

#### Step 1: Identify the business process

The business process analysed in this project is passenger-flight operational performance analysis, with a focus on:

- flight disruptions
- airport traffic comparison
- geographic performance variation
- time-based flight status patterns
- navigation-aid availability comparison
- passenger-related distribution analysis

#### Step 2: Declare the grain

The grain of the fact table is:

**one row per passenger-flight record**

This grain was preserved throughout the ETL process and was not changed by the integration of `navaids.csv`.

#### Step 3: Identify the dimensions

The dimensions used in the warehouse are:

- `dim_date`
- `dim_country`
- `dim_region`
- `dim_airport`
- `dim_passenger`
- `dim_flight_status`

#### Step 4: Identify the facts

The central fact table is `fact_passenger_flight`, which stores the following measures:

- `flight_record_count`
- `delayed_flag`
- `cancelled_flag`
- `ontime_flag`

These measures support aggregation across all five business questions.

### 4.2 Concept Hierarchies

The warehouse design includes the following concept hierarchies:

- Time hierarchy: `Year -> Quarter -> Month`
- Geography hierarchy: `Continent -> Country -> Region -> Airport`
- Passenger grouping: `Age -> Age Group`

In addition, navigation-aid availability is treated as an airport-level descriptive attribute rather than a separate hierarchy. This is because navigation-aid records are many-to-one relative to airports and are more appropriately modelled as airport properties.

### 4.3 StarNet / Snowflake Design

> [Insert Figure 1 here: StarNet diagram]

> [Insert Figure 2 here: Snowflake / dimensional schema diagram]

The warehouse was designed as a star-style dimensional model with a single central fact table and multiple dimensions. Geography is partially normalised through `dim_country` and `dim_region`, while navigation-aid availability is embedded in `dim_airport` via derived attributes such as `has_navaid`, `navaid_count_bucket`, and `navaid_type_group`.

---

## 5. ETL Process

### 5.1 ETL Overview

The ETL process was implemented locally in Python and executed once. The resulting cleaned outputs were reused in both PostgreSQL and Databricks. This approach is consistent with the project announcement and avoided unnecessary duplication of transformation logic.

The ETL process followed the standard pipeline:

- Extract raw CSV files
- Transform and clean data
- Integrate datasets
- Generate staging outputs
- Generate warehouse-ready outputs
- Validate row counts and joins

### 5.2 Raw Row Counts

The source row counts were:

- Airline: 98,619
- Airports: 84,536
- Countries: 249
- Regions: 3,942
- Navaids: 11,010

### 5.3 Main Transformations

The major ETL transformations included:

- standardising whitespace and casing
- normalising `Flight Status` into `On Time`, `Delayed`, and `Cancelled`
- normalising `Gender`
- parsing `Departure Date` into ISO date format
- deriving `month`, `quarter`, and `year`
- deriving `age_group`
- reinterpreting `Arrival Airport` as `departure_airport_code`
- standardising airport, region, and country codes
- aggregating `navaids.csv` to airport level

### 5.4 Integration Logic

The join path used in ETL was:

1. `Airline.departure_airport_code -> airports.iata_code`
2. `airports.iso_region -> regions.code`
3. `airports.iso_country -> countries.code`
4. `airports.ident -> navaids.associated_airport`

The join statistics were:

- Airport IATA matches: 92,807
- Airport IATA unmatched: 5,812
- Region matches: 92,807
- Country matches: 98,619
- Rows with navaid profile: 40,965

### 5.5 Row Retention

A key requirement in the project brief is that the ETL process should not remove more than 5% of rows from the main Airline dataset. In this implementation:

- Raw Airline rows: 98,619
- Cleaned Airline rows: 98,619
- Rows dropped: 0

Therefore, the ETL process fully satisfied the row-retention requirement.

### 5.6 ETL Outputs

The ETL process generated:

#### Staging outputs

- `stg_airline.csv`
- `stg_airports.csv`
- `stg_countries.csv`
- `stg_regions.csv`
- `stg_navaids.csv`
- `stg_navaid_profile_by_airport.csv`
- `cleaned_flight_records.csv`

#### Warehouse-ready outputs

- `dim_date.csv`
- `dim_country.csv`
- `dim_region.csv`
- `dim_airport.csv`
- `dim_passenger.csv`
- `dim_flight_status.csv`
- `fact_passenger_flight.csv`

> [Insert Figure 3 here: ETL workflow screenshot or ETL code screenshot]

> [Insert Figure 4 here: ETL output folder screenshot]

---

## 6. PostgreSQL Warehouse Implementation

### 6.1 Warehouse Tables

The PostgreSQL warehouse contains the following tables:

- `dw.dim_date`
- `dw.dim_country`
- `dw.dim_region`
- `dw.dim_airport`
- `dw.dim_passenger`
- `dw.dim_flight_status`
- `dw.fact_passenger_flight`

Primary keys and foreign keys were defined to preserve the dimensional structure, and indexes were created on fact-table foreign keys to improve query performance.

> [Insert Figure 5 here: PostgreSQL schema screenshot]

### 6.2 Multi-Dimensional Analysis Service / Cube Layer

To satisfy the project requirement of building a multidimensional analysis service solution, cube-like structures were implemented in PostgreSQL using materialized views together with `ROLLUP` and `CUBE` operations. These materialized views act as analysis cubes and support the concept hierarchies defined in the dimensional model.

The following cube-oriented materialized views were created:

- `mv_cube_time_status`
- `mv_cube_geo_status`
- `mv_cube_navaid_geo_status`
- `mv_cube_passenger_status`

These materialized views support time hierarchy analysis, geography hierarchy analysis, navigation-aid analysis, and passenger segment analysis respectively.

> [Insert Figure 6 here: PostgreSQL materialized views / cube screenshot]

---

## 7. Databricks Implementation

The cleaned warehouse-ready CSV files were also loaded into Databricks. Although the project announcement allows the Databricks schema to be simpler than the PostgreSQL implementation, the same cleaned outputs were reused in order to maintain consistency across platforms.

Databricks was used primarily to demonstrate that the transformed warehouse data could be loaded and analysed in an alternative data platform. This confirmed the portability of the ETL outputs and the robustness of the warehouse design.

> [Insert Figure 7 here: Databricks schema screenshot]

> [Insert Figure 8 here: Databricks loading / table screenshot]

---

## 8. SQL Analysis and Visualisation

### 8.1 BQ1: Countries and Regions with Highest Disruption

This business question investigates which countries and regions have the highest number and proportion of delayed or cancelled flights.

The SQL query aggregated disruption counts and disruption rates across country and region levels. The resulting output showed that some countries such as Cape Verde, Iraq, and the Dominican Republic had high combined disruption rates in the filtered output. However, these high rates should be interpreted carefully because some countries may have relatively lower traffic volume compared with larger aviation markets.

> [Insert Figure 9 here: BQ1 visualisation]

**Preliminary interpretation:**
The BQ1 analysis suggests that disruption is not evenly distributed across geographic units. Some smaller markets exhibit very high disruption proportions, while larger markets may contribute more disruption volume in absolute terms. This distinction between rate and volume should be clearly discussed in the final report.

### 8.2 BQ2: Monthly and Quarterly Flight Status Variation

This question analyses how `Flight Status` changes across month and quarter within the observed year.

The SQL result produced monthly counts and rates for `On Time`, `Delayed`, and `Cancelled`. For example, January showed a relatively balanced distribution, with `Delayed` slightly higher than the other two classes. Since the dataset covers only one observed year, this analysis should be discussed as an intra-year distribution comparison rather than a long-term trend analysis.

> [Insert Figure 10 here: BQ2 visualisation]

**Preliminary interpretation:**
The monthly variation appears moderate rather than dramatic. This is consistent with the overall near-balanced distribution of `Flight Status` in the dataset.

### 8.3 BQ3: Traffic Volume and Airport-Level Status Comparison

This business question compares airports by traffic volume and then analyses their flight status composition.

The PostgreSQL cube query produced airport-level outputs showing total records, status counts, and status rates. The visualisation focuses on top airports by traffic volume and compares their disruption composition.

> [Insert Figure 11 here: BQ3 visualisation]

**Preliminary interpretation:**
Airport-level distributions vary, but the reliability of this analysis depends on stable airport identification. This is why the query logic needs to be validated carefully to avoid issues caused by non-unique airport names.

### 8.4 BQ4: Navigation-Aid Availability Across Geography Hierarchies

This is the most distinctive business question in the project because it introduces the external `navaids.csv` dataset and integrates it into the dimensional model.

The query compares disruption patterns across `Airport -> Region -> Country -> Continent` hierarchies while grouping airports by `navaid_count_bucket`. Sample outputs show that certain airport-level records with `navaid_count_bucket = 0`, `1`, or `2-3` display noticeable differences in combined disruption rate.

> [Insert Figure 12 here: BQ4 visualisation]

**Preliminary interpretation:**
This analysis does not prove causality, but it does show that navigation-aid availability can be used as a meaningful comparative dimension when analysing flight-status performance across geographies.

### 8.5 BQ5: Time, Geography, and Passenger Attribute Combinations

BQ5 investigates which combinations of time, geography, and passenger-related attributes are associated with different flight status outcomes.

The current SQL output focuses on combinations of:

- `quarter`
- `continent_name`
- `age_group`
- `flight_status`

This keeps the result interpretable while still reflecting the multidimensional nature of the question.

> [Insert Figure 13 here: BQ5 visualisation]

**Preliminary interpretation:**
BQ5 is broader than the other business questions, so the final visualisation should remain focused. A matrix-style layout is likely to be the most suitable format because it can display structural differences across quarter, continent, age group, and status without becoming visually overloaded.

---

## 9. Association Rule Mining

### 9.1 Method

Association rule mining was conducted using Python only, in accordance with the project requirement. A pure Python Apriori-style implementation was used to generate and evaluate rules whose right-hand side was restricted to `Flight Status`.

The mining attributes used were:

- `quarter`
- `continent_name`
- `airport_type`
- `scheduled_service`
- `navaid_count_bucket`
- `age_group`

Rules were filtered using the following thresholds:

- `min_support = 0.01`
- `min_confidence = 0.34`
- `max_antecedent_size = 3`

The baseline distribution of `Flight Status` in the dataset was almost perfectly balanced:

- `Cancelled`: 0.3340
- `Delayed`: 0.3329
- `On Time`: 0.3331

This balanced distribution limits the possibility of discovering very strong rules, which is why most resulting lift values are only slightly above 1.0.

### 9.2 Top Rules

The top 5 retained rules were:

1. `continent_name=Europe AND navaid_count_bucket=2-3 AND scheduled_service=yes -> Delayed`
   - support = 0.0104
   - confidence = 0.3661
   - lift = 1.0996

2. `continent_name=Europe AND navaid_count_bucket=2-3 -> Delayed`
   - support = 0.0123
   - confidence = 0.3638
   - lift = 1.0927

3. `airport_type=medium_airport AND continent_name=North America AND quarter=Q4 -> Cancelled`
   - support = 0.0104
   - confidence = 0.3560
   - lift = 1.0659

4. `airport_type=medium_airport AND quarter=Q3 AND scheduled_service=no -> On Time`
   - support = 0.0120
   - confidence = 0.3545
   - lift = 1.0642

5. `airport_type=medium_airport AND continent_name=North America AND navaid_count_bucket=1 -> Cancelled`
   - support = 0.0144
   - confidence = 0.3550
   - lift = 1.0628

### 9.3 Interpretation

The association rules are directionally meaningful but not extremely strong. The strongest rules suggest that geography, quarter, airport type, scheduled-service status, and navigation-aid availability are more relevant to flight-status outcomes than passenger demographic variables.

In particular, Europe combined with medium navigation-aid coverage (`navaid_count_bucket = 2-3`) is associated with above-baseline delay risk, while North American medium airports in Q4 or with low navigation-aid coverage (`navaid_count_bucket = 1`) are associated with above-baseline cancellation risk.

### 9.4 Government Recommendations

Based on the mined rules, the following recommendations can be proposed:

1. Governments and aviation regulators should prioritise resilience reviews for high-traffic scheduled-service airports in Europe and North America, especially in Q4.
2. Navigation-aid upgrades should be prioritised for airports with medium or low recorded navaid coverage, because these categories appear repeatedly in above-baseline disruption rules.
3. Seasonal resource allocation should be improved by using quarter-based disruption patterns to guide staffing, maintenance planning, and contingency support.

> [Insert Figure 14 here: Association rule mining summary table or rules screenshot]

---

## 10. Limitations

This project has several limitations that should be acknowledged.

First, the Airline dataset contains only one observed year, so time-based analysis should not be overstated as long-term trend analysis.

Second, the original data contains a known semantic issue in the `Arrival Airport` field, which required interpretation and correction during ETL. Although this issue was handled carefully, it highlights the importance of source-data validation.

Third, the `Flight Status` classes are almost perfectly balanced, which limits the strength of both predictive differentiation and association rule mining. As a result, many discovered patterns are best interpreted as weak but meaningful statistical tendencies rather than strong causal relationships.

Fourth, the current visualisation layer still requires refinement in layout, hierarchy presentation, and storytelling quality before final submission.

---

## 11. Conclusion

This project designed and implemented a dimensional airline data warehouse using the Airline dataset together with airport, country, region, and navigation-aid enrichment data. The warehouse was built using Kimball-style dimensional modelling principles, implemented in PostgreSQL and Databricks, and supported by a Python ETL pipeline that preserved the grain of one row per passenger-flight record.

The PostgreSQL implementation included both a dimensional warehouse schema and a cube-oriented multidimensional analysis layer. The resulting SQL queries supported five business questions across time, geography, airport operations, infrastructure attributes, and passenger segments. In addition, Python-based association rule mining revealed operationally relevant but moderate-strength patterns related to `Flight Status`.

Overall, the project demonstrates how a coherent ETL process, dimensional design, and cube-based analysis framework can transform heterogeneous aviation datasets into a warehouse capable of supporting both descriptive analysis and pattern discovery.

---

## 12. References

> [TO DO: Replace the placeholder list below with fully verified IEEE-style references. All entries must be manually checked before submission.]

- Agrawal, R., Imielinski, T., & Swami, A. (1993). Mining association rules between sets of items in large databases. *Proceedings of the 1993 ACM SIGMOD International Conference on Management of Data*.
- Agrawal, R., & Srikant, R. (1994). Fast algorithms for mining association rules. *Proceedings of the 20th International Conference on Very Large Data Bases*.
- [TO DO: Add dimensional modelling / Kimball reference]
- [TO DO: Add any PostgreSQL / Databricks implementation references if cited in report]
