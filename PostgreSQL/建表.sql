CREATE SCHEMA IF NOT EXISTS dw;
SET search_path TO dw;

CREATE TABLE dim_date (
    date_key INT PRIMARY KEY,
    full_date DATE,
    day_of_month INT,
    month INT,
    month_name VARCHAR(20),
    quarter VARCHAR(2),
    year INT
);

CREATE TABLE dim_country (
    country_key INT PRIMARY KEY,
    country_code VARCHAR(20),
    country_name VARCHAR(100),
    continent_name VARCHAR(50)
);

CREATE TABLE dim_region (
    region_key INT PRIMARY KEY,
    region_code VARCHAR(20),
    region_name VARCHAR(100),
    country_code VARCHAR(20),
    continent_name VARCHAR(50)
);

CREATE TABLE dim_airport (
    airport_key INT PRIMARY KEY,
    airport_ident VARCHAR(30),
    airport_name VARCHAR(200),
    departure_airport_code VARCHAR(20),
    airport_type VARCHAR(50),
    municipality VARCHAR(100),
    scheduled_service VARCHAR(20),
    region_code VARCHAR(20),
    country_code VARCHAR(20),
    has_navaid CHAR(1),
    navaid_count INT,
    navaid_count_bucket VARCHAR(10),
    navaid_type_group VARCHAR(50),
    dominant_usage_type VARCHAR(30),
    max_power VARCHAR(20)
);

CREATE TABLE dim_passenger (
    passenger_key INT PRIMARY KEY,
    passenger_id VARCHAR(50),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    gender VARCHAR(20),
    age INT,
    age_group VARCHAR(20),
    nationality VARCHAR(100)
);

CREATE TABLE dim_flight_status (
    flight_status_key INT PRIMARY KEY,
    flight_status VARCHAR(30)
);

CREATE TABLE fact_passenger_flight (
    fact_id INT PRIMARY KEY,
    date_key INT REFERENCES dim_date(date_key),
    airport_key INT REFERENCES dim_airport(airport_key),
    region_key INT REFERENCES dim_region(region_key),
    country_key INT REFERENCES dim_country(country_key),
    passenger_key INT REFERENCES dim_passenger(passenger_key),
    flight_status_key INT REFERENCES dim_flight_status(flight_status_key),
    flight_record_count INT NOT NULL,
    delayed_flag INT NOT NULL,
    cancelled_flag INT NOT NULL,
    ontime_flag INT NOT NULL
);

CREATE INDEX idx_fact_date_key ON fact_passenger_flight(date_key);
CREATE INDEX idx_fact_airport_key ON fact_passenger_flight(airport_key);
CREATE INDEX idx_fact_region_key ON fact_passenger_flight(region_key);
CREATE INDEX idx_fact_country_key ON fact_passenger_flight(country_key);
CREATE INDEX idx_fact_passenger_key ON fact_passenger_flight(passenger_key);
CREATE INDEX idx_fact_status_key ON fact_passenger_flight(flight_status_key);

SELECT COUNT(*) AS dim_date_rows FROM dw.dim_date;
SELECT COUNT(*) AS dim_country_rows FROM dw.dim_country;
SELECT COUNT(*) AS dim_region_rows FROM dw.dim_region;
SELECT COUNT(*) AS dim_airport_rows FROM dw.dim_airport;
SELECT COUNT(*) AS dim_passenger_rows FROM dw.dim_passenger;
SELECT COUNT(*) AS dim_flight_status_rows FROM dw.dim_flight_status;
SELECT COUNT(*) AS fact_rows FROM dw.fact_passenger_flight;

SELECT
    SUM(CASE WHEN date_key IS NULL THEN 1 ELSE 0 END) AS null_date_key,
    SUM(CASE WHEN airport_key IS NULL THEN 1 ELSE 0 END) AS null_airport_key,
    SUM(CASE WHEN region_key IS NULL THEN 1 ELSE 0 END) AS null_region_key,
    SUM(CASE WHEN country_key IS NULL THEN 1 ELSE 0 END) AS null_country_key,
    SUM(CASE WHEN passenger_key IS NULL THEN 1 ELSE 0 END) AS null_passenger_key,
    SUM(CASE WHEN flight_status_key IS NULL THEN 1 ELSE 0 END) AS null_status_key
FROM dw.fact_passenger_flight;

