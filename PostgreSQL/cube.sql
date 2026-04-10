CREATE SCHEMA IF NOT EXISTS dw;

CREATE OR REPLACE VIEW dw.vw_analysis_base AS
SELECT
    d.date_key,
    d.full_date,
    d.year,
    d.quarter,
    d.month,
    d.month_name,
    c.country_key,
    c.country_code,
    c.country_name,
    c.continent_name,
    r.region_key,
    r.region_code,
    r.region_name,
    a.airport_key,
    a.airport_ident,
    a.airport_name,
    a.departure_airport_code,
    a.navaid_count_bucket,
    a.navaid_type_group,
    a.has_navaid,
    p.passenger_key,
    p.age_group,
    p.gender,
    p.nationality,
    fs.flight_status_key,
    fs.flight_status,
    f.flight_record_count,
    f.delayed_flag,
    f.cancelled_flag,
    f.ontime_flag
FROM dw.fact_passenger_flight f
JOIN dw.dim_date d
  ON f.date_key = d.date_key
JOIN dw.dim_country c
  ON f.country_key = c.country_key
JOIN dw.dim_region r
  ON f.region_key = r.region_key
JOIN dw.dim_airport a
  ON f.airport_key = a.airport_key
JOIN dw.dim_passenger p
  ON f.passenger_key = p.passenger_key
JOIN dw.dim_flight_status fs
  ON f.flight_status_key = fs.flight_status_key;

DROP MATERIALIZED VIEW IF EXISTS dw.mv_cube_time_status CASCADE;
CREATE MATERIALIZED VIEW dw.mv_cube_time_status AS
SELECT
    CASE
        WHEN GROUPING(month) = 0 THEN 'Month'
        WHEN GROUPING(quarter) = 0 THEN 'Quarter'
        WHEN GROUPING(year) = 0 THEN 'Year'
        ELSE 'All Time'
    END AS time_level,
    year,
    quarter,
    month,
    CASE
        WHEN GROUPING(month) = 0 THEN MIN(month_name)
        ELSE NULL
    END AS month_name,
    flight_status,
    SUM(flight_record_count) AS total_records,
    SUM(delayed_flag) AS delayed_count,
    SUM(cancelled_flag) AS cancelled_count,
    SUM(ontime_flag) AS ontime_count,
    ROUND(SUM(delayed_flag)::numeric / NULLIF(SUM(flight_record_count), 0), 4) AS delayed_rate,
    ROUND(SUM(cancelled_flag)::numeric / NULLIF(SUM(flight_record_count), 0), 4) AS cancelled_rate,
    ROUND(SUM(ontime_flag)::numeric / NULLIF(SUM(flight_record_count), 0), 4) AS ontime_rate
FROM dw.vw_analysis_base
GROUP BY ROLLUP(year, quarter, month), flight_status;

CREATE INDEX IF NOT EXISTS idx_mv_cube_time_status_level
    ON dw.mv_cube_time_status (time_level, year, quarter, month, flight_status);

DROP MATERIALIZED VIEW IF EXISTS dw.mv_cube_geo_status CASCADE;
CREATE MATERIALIZED VIEW dw.mv_cube_geo_status AS
SELECT
    CASE
        WHEN GROUPING(airport_name) = 0 THEN 'Airport'
        WHEN GROUPING(region_name) = 0 THEN 'Region'
        WHEN GROUPING(country_name) = 0 THEN 'Country'
        WHEN GROUPING(continent_name) = 0 THEN 'Continent'
        ELSE 'All Geography'
    END AS geography_level,
    continent_name,
    country_name,
    region_name,
    airport_name,
    CASE
        WHEN GROUPING(airport_name) = 0 THEN MIN(departure_airport_code)
        ELSE NULL
    END AS departure_airport_code,
    flight_status,
    SUM(flight_record_count) AS total_records,
    SUM(delayed_flag) AS delayed_count,
    SUM(cancelled_flag) AS cancelled_count,
    SUM(ontime_flag) AS ontime_count,
    ROUND(SUM(delayed_flag)::numeric / NULLIF(SUM(flight_record_count), 0), 4) AS delayed_rate,
    ROUND(SUM(cancelled_flag)::numeric / NULLIF(SUM(flight_record_count), 0), 4) AS cancelled_rate,
    ROUND(SUM(ontime_flag)::numeric / NULLIF(SUM(flight_record_count), 0), 4) AS ontime_rate
FROM dw.vw_analysis_base
GROUP BY ROLLUP(continent_name, country_name, region_name, airport_name), flight_status;

CREATE INDEX IF NOT EXISTS idx_mv_cube_geo_status_level
    ON dw.mv_cube_geo_status (geography_level, continent_name, country_name, region_name, flight_status);

DROP MATERIALIZED VIEW IF EXISTS dw.mv_cube_navaid_geo_status CASCADE;
CREATE MATERIALIZED VIEW dw.mv_cube_navaid_geo_status AS
SELECT
    CASE
        WHEN GROUPING(airport_name) = 0 THEN 'Airport'
        WHEN GROUPING(region_name) = 0 THEN 'Region'
        WHEN GROUPING(country_name) = 0 THEN 'Country'
        WHEN GROUPING(continent_name) = 0 THEN 'Continent'
        ELSE 'All Geography'
    END AS geography_level,
    continent_name,
    country_name,
    region_name,
    airport_name,
    navaid_count_bucket,
    navaid_type_group,
    flight_status,
    SUM(flight_record_count) AS total_records,
    SUM(delayed_flag) AS delayed_count,
    SUM(cancelled_flag) AS cancelled_count,
    SUM(ontime_flag) AS ontime_count,
    ROUND(SUM(delayed_flag)::numeric / NULLIF(SUM(flight_record_count), 0), 4) AS delayed_rate,
    ROUND(SUM(cancelled_flag)::numeric / NULLIF(SUM(flight_record_count), 0), 4) AS cancelled_rate,
    ROUND(SUM(ontime_flag)::numeric / NULLIF(SUM(flight_record_count), 0), 4) AS ontime_rate,
    ROUND((SUM(delayed_flag) + SUM(cancelled_flag))::numeric / NULLIF(SUM(flight_record_count), 0), 4) AS combined_disruption_rate
FROM dw.vw_analysis_base
GROUP BY ROLLUP(continent_name, country_name, region_name, airport_name),
         navaid_count_bucket,
         navaid_type_group,
         flight_status;

CREATE INDEX IF NOT EXISTS idx_mv_cube_navaid_geo_status_level
    ON dw.mv_cube_navaid_geo_status (geography_level, continent_name, country_name, region_name, navaid_count_bucket, flight_status);

DROP MATERIALIZED VIEW IF EXISTS dw.mv_cube_passenger_status CASCADE;
CREATE MATERIALIZED VIEW dw.mv_cube_passenger_status AS
SELECT
    quarter,
    continent_name,
    age_group,
    gender,
    flight_status,
    SUM(flight_record_count) AS total_records,
    SUM(delayed_flag) AS delayed_count,
    SUM(cancelled_flag) AS cancelled_count,
    SUM(ontime_flag) AS ontime_count,
    ROUND(SUM(delayed_flag)::numeric / NULLIF(SUM(flight_record_count), 0), 4) AS delayed_rate,
    ROUND(SUM(cancelled_flag)::numeric / NULLIF(SUM(flight_record_count), 0), 4) AS cancelled_rate,
    ROUND(SUM(ontime_flag)::numeric / NULLIF(SUM(flight_record_count), 0), 4) AS ontime_rate
FROM dw.vw_analysis_base
GROUP BY CUBE(quarter, continent_name, age_group, gender), flight_status;

CREATE INDEX IF NOT EXISTS idx_mv_cube_passenger_status_level
    ON dw.mv_cube_passenger_status (quarter, continent_name, age_group, gender, flight_status);

CREATE OR REPLACE PROCEDURE dw.refresh_analysis_cubes()
LANGUAGE SQL
AS $$
    REFRESH MATERIALIZED VIEW dw.mv_cube_time_status;
    REFRESH MATERIALIZED VIEW dw.mv_cube_geo_status;
    REFRESH MATERIALIZED VIEW dw.mv_cube_navaid_geo_status;
    REFRESH MATERIALIZED VIEW dw.mv_cube_passenger_status;
$$;
