-- ============================================
-- PostgreSQL 一体化脚本
-- 项目：Data Warehouse Project 1
-- 说明：
-- 1. 本脚本将“建表脚本 + cube 层脚本 + 出图查询脚本”合并为一个文件。
-- 2. 为了避免重复执行时报错，本脚本中的建表部分使用 IF NOT EXISTS。
-- 3. 你仍然需要在 pgAdmin 中手动导入本地 CSV 数据，SQL 无法替代“本地拖入/导入”这一步。
-- 4. 推荐执行顺序：
--    第一步：运行“第 1 部分 建表”
--    第二步：在 pgAdmin 中导入 7 个 CSV
--    第三步：运行“第 2 部分 验证导入”
--    第四步：运行“第 3 部分 建立 cube 层”
--    第五步：运行“第 4 部分 刷新 cube”
--    第六步：运行“第 5 部分 业务查询（出图版）”
-- ============================================


-- ============================================
-- 第 1 部分：创建 schema、维表、事实表
-- 这部分通常只需要执行一次
-- ============================================

CREATE SCHEMA IF NOT EXISTS dw;
SET search_path TO dw;

CREATE TABLE IF NOT EXISTS dim_date (
    date_key INT PRIMARY KEY,
    full_date DATE,
    day_of_month INT,
    month INT,
    month_name VARCHAR(20),
    quarter VARCHAR(2),
    year INT
);

CREATE TABLE IF NOT EXISTS dim_country (
    country_key INT PRIMARY KEY,
    country_code VARCHAR(20),
    country_name VARCHAR(100),
    continent_name VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS dim_region (
    region_key INT PRIMARY KEY,
    region_code VARCHAR(20),
    region_name VARCHAR(100),
    country_code VARCHAR(20),
    continent_name VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS dim_airport (
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

CREATE TABLE IF NOT EXISTS dim_passenger (
    passenger_key INT PRIMARY KEY,
    passenger_id VARCHAR(50),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    gender VARCHAR(20),
    age INT,
    age_group VARCHAR(20),
    nationality VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS dim_flight_status (
    flight_status_key INT PRIMARY KEY,
    flight_status VARCHAR(30)
);

CREATE TABLE IF NOT EXISTS fact_passenger_flight (
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

CREATE INDEX IF NOT EXISTS idx_fact_date_key ON fact_passenger_flight(date_key);
CREATE INDEX IF NOT EXISTS idx_fact_airport_key ON fact_passenger_flight(airport_key);
CREATE INDEX IF NOT EXISTS idx_fact_region_key ON fact_passenger_flight(region_key);
CREATE INDEX IF NOT EXISTS idx_fact_country_key ON fact_passenger_flight(country_key);
CREATE INDEX IF NOT EXISTS idx_fact_passenger_key ON fact_passenger_flight(passenger_key);
CREATE INDEX IF NOT EXISTS idx_fact_status_key ON fact_passenger_flight(flight_status_key);


-- ============================================
-- 第 2 部分：导入完成后的基础验证
-- 在 pgAdmin 手动导入 7 个 CSV 之后执行
-- ============================================

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


-- ============================================
-- 第 3 部分：建立多维分析服务 / cube 层
-- 说明：
-- 1. PostgreSQL 没有 SSAS 那种图形化 cube，对课程项目来说，
--    最稳妥的做法是用 materialized view + ROLLUP / CUBE
--    来实现多维分析服务。
-- 2. 下列 cube 与 StarNet 概念层级对应：
--    时间层级：Year -> Quarter -> Month
--    地理层级：Continent -> Country -> Region -> Airport
--    Navaid：作为 Airport 维度的分析属性
-- ============================================

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

-- 创建或替换一个叫 refresh_analysis_cubes 的存储过程
CREATE OR REPLACE PROCEDURE dw.refresh_analysis_cubes()
LANGUAGE SQL
AS $$
    -- 刷新时间维度的 cube
    REFRESH MATERIALIZED VIEW dw.mv_cube_time_status;

    -- 刷新地理层级的 cube
    REFRESH MATERIALIZED VIEW dw.mv_cube_geo_status;

    -- 刷新 navaid + 地理层级的 cube
    REFRESH MATERIALIZED VIEW dw.mv_cube_navaid_geo_status;

    -- 刷新乘客属性相关的 cube
    REFRESH MATERIALIZED VIEW dw.mv_cube_passenger_status;
$$;



-- ============================================
-- 第 4 部分：刷新 cube
-- 每次重新导入维表/事实表数据后，都应该执行一次
-- ============================================

CALL dw.refresh_analysis_cubes();


-- ============================================
-- 第 5 部分：基于 cube 的业务查询（最终出图版）
-- 说明：
-- 1. 这些查询是给 Power BI / Tableau 出图用的
-- 2. 可以在 pgAdmin 里运行后，把结果导出为 CSV
-- 3. 每条查询都直接使用 cube 视图，而不是直接扫事实表
-- ============================================


-- --------------------------------------------
-- BQ1
-- 哪些国家和地区具有最高的延误/取消数量与比例？
-- 推荐图表：Clustered Bar / Stacked Bar
-- --------------------------------------------
WITH country_metrics AS (
    SELECT
        'Country' AS geography_level,
        country_name AS geography_name,
        SUM(total_records) AS total_records,
        SUM(delayed_count) AS delayed_count,
        SUM(cancelled_count) AS cancelled_count,
        SUM(delayed_count) + SUM(cancelled_count) AS combined_disruption_count
    FROM dw.mv_cube_geo_status
    WHERE geography_level = 'Country'
      AND country_name <> 'Unknown Country'
    GROUP BY country_name
    HAVING SUM(total_records) >= 100
), region_metrics AS (
    SELECT
        'Region' AS geography_level,
        region_name AS geography_name,
        SUM(total_records) AS total_records,
        SUM(delayed_count) AS delayed_count,
        SUM(cancelled_count) AS cancelled_count,
        SUM(delayed_count) + SUM(cancelled_count) AS combined_disruption_count
    FROM dw.mv_cube_geo_status
    WHERE geography_level = 'Region'
      AND region_name <> 'Unknown Region'
    GROUP BY region_name
    HAVING SUM(total_records) >= 100
), combined AS (
    SELECT
        geography_level,
        geography_name,
        total_records,
        delayed_count,
        cancelled_count,
        combined_disruption_count,
        ROUND(delayed_count::numeric / NULLIF(total_records, 0), 4) AS delayed_rate,
        ROUND(cancelled_count::numeric / NULLIF(total_records, 0), 4) AS cancelled_rate,
        ROUND(combined_disruption_count::numeric / NULLIF(total_records, 0), 4) AS combined_disruption_rate
    FROM country_metrics

    UNION ALL

    SELECT
        geography_level,
        geography_name,
        total_records,
        delayed_count,
        cancelled_count,
        combined_disruption_count,
        ROUND(delayed_count::numeric / NULLIF(total_records, 0), 4) AS delayed_rate,
        ROUND(cancelled_count::numeric / NULLIF(total_records, 0), 4) AS cancelled_rate,
        ROUND(combined_disruption_count::numeric / NULLIF(total_records, 0), 4) AS combined_disruption_rate
    FROM region_metrics
), ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY geography_level
            ORDER BY combined_disruption_rate DESC, combined_disruption_count DESC, total_records DESC
        ) AS rn
    FROM combined
)
SELECT
    geography_level,
    geography_name,
    total_records,
    delayed_count,
    cancelled_count,
    combined_disruption_count,
    delayed_rate,
    cancelled_rate,
    combined_disruption_rate
FROM ranked
WHERE rn <= 10
ORDER BY geography_level, rn;


-- --------------------------------------------
-- BQ2
-- 在观察年份内，航班状态如何随月份和季度变化？
-- 推荐图表：100% Stacked Column / Line Chart
-- --------------------------------------------
SELECT
    year,
    quarter,
    month,
    month_name,
    flight_status,
    total_records AS status_count,
    ROUND(total_records::numeric / NULLIF(SUM(total_records) OVER (PARTITION BY year, quarter, month), 0), 4) AS status_rate
FROM dw.mv_cube_time_status
WHERE time_level = 'Month'
ORDER BY
    year,
    month,
    CASE flight_status
        WHEN 'On Time' THEN 1
        WHEN 'Delayed' THEN 2
        WHEN 'Cancelled' THEN 3
        ELSE 4
    END;


-- --------------------------------------------
-- BQ3
-- 哪些机场的客流量最高，它们的航班状态构成如何？
-- 推荐图表：Top 10 Stacked Bar
-- --------------------------------------------
WITH airport_totals AS (
    SELECT
        airport_name,
        SUM(total_records) AS total_records
    FROM dw.mv_cube_geo_status
    WHERE geography_level = 'Airport'
      AND airport_name <> 'Unknown Airport'
    GROUP BY airport_name
), top_airports AS (
    SELECT
        airport_name,
        total_records
    FROM airport_totals
    ORDER BY total_records DESC
    LIMIT 10
)
SELECT
    g.airport_name,
    t.total_records,
    g.flight_status,
    g.total_records AS status_count,
    ROUND(g.total_records::numeric / NULLIF(t.total_records, 0), 4) AS status_rate
FROM dw.mv_cube_geo_status g
JOIN top_airports t
  ON g.airport_name = t.airport_name
WHERE g.geography_level = 'Airport'
ORDER BY t.total_records DESC, g.airport_name, g.flight_status;


-- --------------------------------------------
-- BQ4
-- 在机场 -> 地区 -> 国家 -> 大洲层级中，
-- 不同导航设施可用性水平下的航班表现如何变化？
-- 推荐图表：Heatmap / Small Multiples / Drill-down Bar
-- --------------------------------------------
WITH ranked_country AS (
    SELECT
        geography_level,
        country_name AS hierarchy_name,
        navaid_count_bucket,
        SUM(total_records) AS total_records,
        SUM(delayed_count) AS delayed_count,
        SUM(cancelled_count) AS cancelled_count,
        SUM(ontime_count) AS ontime_count
    FROM dw.mv_cube_navaid_geo_status
    WHERE geography_level = 'Country'
      AND country_name <> 'Unknown Country'
    GROUP BY geography_level, country_name, navaid_count_bucket
), top_countries AS (
    SELECT
        country_name
    FROM (
        SELECT
            country_name,
            SUM(total_records) AS total_records,
            ROW_NUMBER() OVER (ORDER BY SUM(total_records) DESC) AS rn
        FROM dw.mv_cube_navaid_geo_status
        WHERE geography_level = 'Country'
          AND country_name <> 'Unknown Country'
        GROUP BY country_name
    ) t
    WHERE rn <= 10
), ranked_region AS (
    SELECT
        geography_level,
        region_name AS hierarchy_name,
        navaid_count_bucket,
        SUM(total_records) AS total_records,
        SUM(delayed_count) AS delayed_count,
        SUM(cancelled_count) AS cancelled_count,
        SUM(ontime_count) AS ontime_count
    FROM dw.mv_cube_navaid_geo_status
    WHERE geography_level = 'Region'
      AND region_name <> 'Unknown Region'
    GROUP BY geography_level, region_name, navaid_count_bucket
), top_regions AS (
    SELECT
        region_name
    FROM (
        SELECT
            region_name,
            SUM(total_records) AS total_records,
            ROW_NUMBER() OVER (ORDER BY SUM(total_records) DESC) AS rn
        FROM dw.mv_cube_navaid_geo_status
        WHERE geography_level = 'Region'
          AND region_name <> 'Unknown Region'
        GROUP BY region_name
    ) t
    WHERE rn <= 10
), ranked_airport AS (
    SELECT
        geography_level,
        airport_name AS hierarchy_name,
        navaid_count_bucket,
        SUM(total_records) AS total_records,
        SUM(delayed_count) AS delayed_count,
        SUM(cancelled_count) AS cancelled_count,
        SUM(ontime_count) AS ontime_count
    FROM dw.mv_cube_navaid_geo_status
    WHERE geography_level = 'Airport'
      AND airport_name <> 'Unknown Airport'
    GROUP BY geography_level, airport_name, navaid_count_bucket
), top_airports AS (
    SELECT
        airport_name
    FROM (
        SELECT
            airport_name,
            SUM(total_records) AS total_records,
            ROW_NUMBER() OVER (ORDER BY SUM(total_records) DESC) AS rn
        FROM dw.mv_cube_navaid_geo_status
        WHERE geography_level = 'Airport'
          AND airport_name <> 'Unknown Airport'
        GROUP BY airport_name
    ) t
    WHERE rn <= 10
)
SELECT
    'Continent' AS hierarchy_level,
    continent_name AS hierarchy_name,
    navaid_count_bucket,
    SUM(total_records) AS total_records,
    ROUND(SUM(delayed_count)::numeric / NULLIF(SUM(total_records), 0), 4) AS delayed_rate,
    ROUND(SUM(cancelled_count)::numeric / NULLIF(SUM(total_records), 0), 4) AS cancelled_rate,
    ROUND(SUM(ontime_count)::numeric / NULLIF(SUM(total_records), 0), 4) AS ontime_rate,
    ROUND((SUM(delayed_count) + SUM(cancelled_count))::numeric / NULLIF(SUM(total_records), 0), 4) AS combined_disruption_rate
FROM dw.mv_cube_navaid_geo_status
WHERE geography_level = 'Continent'
GROUP BY continent_name, navaid_count_bucket

UNION ALL

SELECT
    geography_level,
    hierarchy_name,
    navaid_count_bucket,
    total_records,
    ROUND(delayed_count::numeric / NULLIF(total_records, 0), 4) AS delayed_rate,
    ROUND(cancelled_count::numeric / NULLIF(total_records, 0), 4) AS cancelled_rate,
    ROUND(ontime_count::numeric / NULLIF(total_records, 0), 4) AS ontime_rate,
    ROUND((delayed_count + cancelled_count)::numeric / NULLIF(total_records, 0), 4) AS combined_disruption_rate
FROM ranked_country
WHERE hierarchy_name IN (SELECT country_name FROM top_countries)

UNION ALL

SELECT
    geography_level,
    hierarchy_name,
    navaid_count_bucket,
    total_records,
    ROUND(delayed_count::numeric / NULLIF(total_records, 0), 4) AS delayed_rate,
    ROUND(cancelled_count::numeric / NULLIF(total_records, 0), 4) AS cancelled_rate,
    ROUND(ontime_count::numeric / NULLIF(total_records, 0), 4) AS ontime_rate,
    ROUND((delayed_count + cancelled_count)::numeric / NULLIF(total_records, 0), 4) AS combined_disruption_rate
FROM ranked_region
WHERE hierarchy_name IN (SELECT region_name FROM top_regions)

UNION ALL

SELECT
    geography_level,
    hierarchy_name,
    navaid_count_bucket,
    total_records,
    ROUND(delayed_count::numeric / NULLIF(total_records, 0), 4) AS delayed_rate,
    ROUND(cancelled_count::numeric / NULLIF(total_records, 0), 4) AS cancelled_rate,
    ROUND(ontime_count::numeric / NULLIF(total_records, 0), 4) AS ontime_rate,
    ROUND((delayed_count + cancelled_count)::numeric / NULLIF(total_records, 0), 4) AS combined_disruption_rate
FROM ranked_airport
WHERE hierarchy_name IN (SELECT airport_name FROM top_airports)

ORDER BY hierarchy_level, hierarchy_name, navaid_count_bucket;


-- --------------------------------------------
-- BQ5
-- 哪些“时间 + 地理 + 乘客属性”的组合与不同航班状态相关？
-- 当前出图粒度：Quarter + Continent + Age Group + Flight Status
-- 推荐图表：Heatmap / Matrix
-- --------------------------------------------
SELECT
    quarter,
    continent_name,
    age_group,
    flight_status,
    total_records AS status_count,
    ROUND(total_records::numeric / NULLIF(SUM(total_records) OVER (PARTITION BY quarter, continent_name, age_group), 0), 4) AS status_rate
FROM dw.mv_cube_passenger_status
WHERE quarter IS NOT NULL
  AND continent_name IS NOT NULL
  AND age_group IS NOT NULL
  AND gender IS NULL
ORDER BY
    quarter,
    continent_name,
    age_group,
    CASE flight_status
        WHEN 'On Time' THEN 1
        WHEN 'Delayed' THEN 2
        WHEN 'Cancelled' THEN 3
        ELSE 4
    END;
