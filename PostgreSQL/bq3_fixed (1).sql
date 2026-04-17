-- BQ3
-- Which airports handle the greatest traffic volume, and how do their flight status distributions compare?
-- Revised version:
-- airport names are not globally unique, so ranking must use airport identifiers.

WITH airport_totals AS (
    SELECT
        airport_ident,
        airport_name,
        SUM(total_records) AS total_records
    FROM dw.mv_cube_geo_status
    WHERE geography_level = 'Airport'
      AND airport_name <> 'Unknown Airport'
      AND airport_ident IS NOT NULL
    GROUP BY airport_ident, airport_name
),
top_airports AS (
    SELECT
        airport_ident,
        airport_name,
        total_records
    FROM airport_totals
    ORDER BY total_records DESC, airport_ident
    LIMIT 10
)
SELECT
    t.airport_ident,
    t.airport_name,
    t.total_records,
    g.flight_status,
    g.total_records AS status_count,
    ROUND(g.total_records::numeric / NULLIF(t.total_records, 0), 4) AS status_rate
FROM dw.mv_cube_geo_status g
JOIN top_airports t
  ON g.airport_ident = t.airport_ident
 AND g.airport_name = t.airport_name
WHERE g.geography_level = 'Airport'
ORDER BY
    t.total_records DESC,
    t.airport_ident,
    CASE g.flight_status
        WHEN 'On Time' THEN 1
        WHEN 'Delayed' THEN 2
        WHEN 'Cancelled' THEN 3
        ELSE 4
    END;
