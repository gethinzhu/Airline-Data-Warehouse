# Association Rule Mining Summary

## Algorithm

This analysis used an Apriori-style, level-wise association rule mining approach implemented in pure Python. Candidate antecedent itemsets of size 1 to 3 were generated from selected categorical attributes, then support, confidence, and lift were computed for rules whose right-hand side was `Flight Status` only.

Selected mining attributes:
- `quarter`
- `continent_name`
- `airport_type`
- `scheduled_service`
- `navaid_count_bucket`
- `age_group`

Excluded high-cardinality identifiers and names to avoid sparse or trivial rules:
- `passenger_id`, `first_name`, `last_name`, `pilot_name`, `airport_ident`, `departure_airport_code`, exact `full_date`

Minimum thresholds used:
- `min_support = 0.01`
- `min_confidence = 0.34`
- `max_antecedent_size = 3`

Baseline flight-status distribution:
- `Cancelled`: 0.3340
- `Delayed`: 0.3329
- `On Time`: 0.3331

Rules retained after filtering: `149`

## Top Rules

### Rule 1

- Rule: `continent_name=Europe AND navaid_count_bucket=2-3 AND scheduled_service=yes -> flight_status=Delayed`
- Support: `0.0104`
- Confidence: `0.3661`
- Lift: `1.0996`
- Plain English: Among records in Europe, airports with 2 to 3 recorded navaids, airports with scheduled service, the probability of `Delayed` is `0.3661`, which is `1.0996` times the dataset-wide baseline for `Delayed`.

### Rule 2

- Rule: `continent_name=Europe AND navaid_count_bucket=2-3 -> flight_status=Delayed`
- Support: `0.0123`
- Confidence: `0.3638`
- Lift: `1.0927`
- Plain English: Among records in Europe, airports with 2 to 3 recorded navaids, the probability of `Delayed` is `0.3638`, which is `1.0927` times the dataset-wide baseline for `Delayed`.

### Rule 3

- Rule: `airport_type=medium_airport AND continent_name=North America AND quarter=Q4 -> flight_status=Cancelled`
- Support: `0.0104`
- Confidence: `0.3560`
- Lift: `1.0659`
- Plain English: Among records at medium airports, in North America, in Q4, the probability of `Cancelled` is `0.3560`, which is `1.0659` times the dataset-wide baseline for `Cancelled`.

### Rule 4

- Rule: `airport_type=medium_airport AND quarter=Q3 AND scheduled_service=no -> flight_status=On Time`
- Support: `0.0120`
- Confidence: `0.3545`
- Lift: `1.0642`
- Plain English: Among records at medium airports, in Q3, airports without scheduled service, the probability of `On Time` is `0.3545`, which is `1.0642` times the dataset-wide baseline for `On Time`.

### Rule 5

- Rule: `airport_type=medium_airport AND continent_name=North America AND navaid_count_bucket=1 -> flight_status=Cancelled`
- Support: `0.0144`
- Confidence: `0.3550`
- Lift: `1.0628`
- Plain English: Among records at medium airports, in North America, airports with 1 recorded navaid, the probability of `Cancelled` is `0.3550`, which is `1.0628` times the dataset-wide baseline for `Cancelled`.

## Insights

The discovered rules are directionally useful but not very strong. Most lifts are only slightly above 1.0, which means the antecedents raise the probability of the right-hand-side flight status only modestly.
This weak signal is consistent with the dataset structure: the three flight-status classes are almost perfectly balanced, so there is limited statistical room for any attribute combination to sharply separate one class from the others.
The strongest operational rules concentrate around geography, quarter, airport type, scheduled-service status, and navigation-aid availability rather than passenger demographics. That makes them more suitable for infrastructure and operations recommendations than for passenger-policy targeting.
Several potentially high-lift combinations with very small support were deliberately filtered out. This avoids over-interpreting rare patterns that are unlikely to be robust enough for policy use.

## Recommendations

- Prioritise operational resilience reviews for busy scheduled-service airports in Europe and North America where the mined rules show above-baseline delayed or cancelled outcomes, especially in Q4.
- Target navigation-aid upgrades and redundancy planning at airports that fall into the 1 or 2-3 navaid buckets, because several of the strongest rules concentrate disruption in these medium-coverage categories rather than at airports with no traffic significance.
- Use quarter-based disruption rules to guide seasonal staffing, maintenance windows, and contingency funding, with extra attention to Q4 cancellation risk and the medium-airport segment.

## References

- Agrawal, R., Imielinski, T., & Swami, A. (1993). Mining association rules between sets of items in large databases. *Proceedings of the 1993 ACM SIGMOD International Conference on Management of Data*.
- Agrawal, R., & Srikant, R. (1994). Fast algorithms for mining association rules. *Proceedings of the 20th International Conference on Very Large Data Bases*.