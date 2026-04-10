-- Refresh cube layer after any fact/dimension reload.
CALL dw.refresh_analysis_cubes();

-- BQ1
-- Which countries and regions have the highest number and proportion of delayed or cancelled flights?
WITH combined AS (
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

    UNION ALL

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
), ranked AS (
    SELECT
        geography_level,
        geography_name,
        total_records,
        delayed_count,
        cancelled_count,
        combined_disruption_count,
        ROUND(delayed_count::numeric / NULLIF(total_records, 0), 4) AS delayed_rate,
        ROUND(cancelled_count::numeric / NULLIF(total_records, 0), 4) AS cancelled_rate,
        ROUND(combined_disruption_count::numeric / NULLIF(total_records, 0), 4) AS combined_disruption_rate,
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


-- BQ2
-- How does flight status change across month and quarter within the observed year?
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


-- BQ3
-- Which airports handle the greatest traffic volume, and how do their flight status distributions compare?
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


-- BQ4
-- How does flight status performance vary across airport, region, country, and continent hierarchies
-- with different levels of navigation-aid availability?
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


-- BQ5
-- Which combinations of time, geographic, and passenger-related attributes are associated
-- with different flight status outcomes?
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
