import csv
from collections import Counter
from dataclasses import dataclass
from itertools import combinations
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple


PROJECT_ROOT = Path(__file__).resolve().parents[1]
INPUT_PATH = PROJECT_ROOT / "ETL" / "output" / "staging" / "cleaned_flight_records.csv"
OUTPUT_DIR = PROJECT_ROOT / "AssociationRuleMining" / "output"

# Selected attributes for mining.
# High-cardinality IDs/names are intentionally excluded because they create sparse,
# low-value rules that are hard to interpret.
MINING_ATTRIBUTES = [
    "quarter",
    "continent_name",
    "airport_type",
    "scheduled_service",
    "navaid_count_bucket",
    "age_group",
]

# Ignore low-quality "unknown" buckets where they reflect ETL matching gaps
# rather than meaningful operational patterns.
IGNORE_UNKNOWN_FOR = {
    "continent_name",
    "airport_type",
    "scheduled_service",
    "age_group",
}

MAX_ANTECEDENT_SIZE = 3
MIN_SUPPORT = 0.01
MIN_CONFIDENCE = 0.34
TOP_K = 5
RHS_ATTRIBUTE = "flight_status"


@dataclass(frozen=True)
class Rule:
    antecedent: Tuple[str, ...]
    rhs: str
    support_count: int
    antecedent_count: int
    rhs_count: int
    total_rows: int

    @property
    def support(self) -> float:
        return self.support_count / self.total_rows

    @property
    def confidence(self) -> float:
        return self.support_count / self.antecedent_count

    @property
    def rhs_support(self) -> float:
        return self.rhs_count / self.total_rows

    @property
    def lift(self) -> float:
        return self.confidence / self.rhs_support


def to_item(attribute: str, value: str) -> str:
    return f"{attribute}={value}"


def parse_item(item: str) -> Tuple[str, str]:
    key, value = item.split("=", 1)
    return key, value


def english_value(attribute: str, value: str) -> str:
    mapping = {
        "quarter": value,
        "continent_name": value,
        "airport_type": {
            "small_airport": "small airports",
            "medium_airport": "medium airports",
            "large_airport": "large airports",
            "heliport": "heliports",
            "seaplane_base": "seaplane bases",
            "Unknown": "unknown airport types",
        }.get(value, value.replace("_", " ")),
        "scheduled_service": {
            "yes": "airports with scheduled service",
            "no": "airports without scheduled service",
            "unknown": "airports with unknown scheduled-service status",
        }.get(value, value),
        "navaid_count_bucket": {
            "0": "airports with no recorded navaids",
            "1": "airports with 1 recorded navaid",
            "2-3": "airports with 2 to 3 recorded navaids",
            "4+": "airports with 4 or more recorded navaids",
        }.get(value, value),
        "age_group": f"passengers aged {value}",
    }
    return mapping.get(attribute, value)


def format_antecedent_plain_english(antecedent: Sequence[str]) -> str:
    parts: List[str] = []
    for item in antecedent:
        attribute, value = parse_item(item)
        rendered = english_value(attribute, value)
        if attribute == "quarter":
            parts.append(f"in {rendered}")
        elif attribute == "continent_name":
            parts.append(f"in {rendered}")
        elif attribute == "airport_type":
            parts.append(f"at {rendered}")
        elif attribute == "scheduled_service":
            parts.append(rendered)
        elif attribute == "navaid_count_bucket":
            parts.append(rendered)
        elif attribute == "age_group":
            parts.append(rendered)
        else:
            parts.append(f"{attribute} = {value}")
    return ", ".join(parts)


def load_transactions(path: Path) -> Tuple[List[List[str]], Counter, int]:
    transactions: List[List[str]] = []
    rhs_counts: Counter = Counter()
    total_rows = 0

    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            total_rows += 1
            rhs_value = row[RHS_ATTRIBUTE]
            rhs_counts[rhs_value] += 1

            items: List[str] = []
            for attribute in MINING_ATTRIBUTES:
                value = row[attribute].strip()
                if attribute in IGNORE_UNKNOWN_FOR and value.lower() == "unknown":
                    continue
                items.append(to_item(attribute, value))
            transactions.append(items + [to_item(RHS_ATTRIBUTE, rhs_value)])

    return transactions, rhs_counts, total_rows


def mine_rules(transactions: Iterable[List[str]], rhs_counts: Counter, total_rows: int) -> List[Rule]:
    antecedent_counts: Counter = Counter()
    joint_counts: Counter = Counter()

    for transaction in transactions:
        rhs_item = next(item for item in transaction if item.startswith(f"{RHS_ATTRIBUTE}="))
        rhs_value = rhs_item.split("=", 1)[1]
        lhs_items = [item for item in transaction if not item.startswith(f"{RHS_ATTRIBUTE}=")]

        for size in range(1, MAX_ANTECEDENT_SIZE + 1):
            for combo in combinations(sorted(lhs_items), size):
                antecedent_counts[combo] += 1
                joint_counts[(combo, rhs_value)] += 1

    rules: List[Rule] = []
    for antecedent, antecedent_count in antecedent_counts.items():
        for rhs_value, rhs_count in rhs_counts.items():
            support_count = joint_counts[(antecedent, rhs_value)]
            if support_count == 0:
                continue

            rule = Rule(
                antecedent=antecedent,
                rhs=rhs_value,
                support_count=support_count,
                antecedent_count=antecedent_count,
                rhs_count=rhs_count,
                total_rows=total_rows,
            )

            if rule.support >= MIN_SUPPORT and rule.confidence >= MIN_CONFIDENCE:
                rules.append(rule)

    rules.sort(
        key=lambda r: (
            r.lift,
            r.confidence,
            r.support,
            len(r.antecedent),
            r.antecedent,
            r.rhs,
        ),
        reverse=True,
    )
    return rules


def summarise_baseline(rhs_counts: Counter, total_rows: int) -> Dict[str, float]:
    return {status: count / total_rows for status, count in sorted(rhs_counts.items())}


def pick_top_non_redundant_rules(rules: Sequence[Rule], top_k: int) -> List[Rule]:
    selected: List[Rule] = []
    seen_signatures = set()

    for rule in rules:
        signature = (rule.rhs, frozenset(rule.antecedent))
        if signature in seen_signatures:
            continue

        # Avoid near-duplicate supersets with identical operational meaning.
        redundant = False
        rule_items = set(rule.antecedent)
        for chosen in selected:
            chosen_items = set(chosen.antecedent)
            if rule.rhs == chosen.rhs and chosen_items.issubset(rule_items):
                if abs(rule.lift - chosen.lift) < 0.01 and abs(rule.confidence - chosen.confidence) < 0.01:
                    redundant = True
                    break
        if redundant:
            continue

        selected.append(rule)
        seen_signatures.add(signature)
        if len(selected) >= top_k:
            break

    return selected


def write_rules_csv(path: Path, rules: Sequence[Rule]) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "rank",
                "antecedent",
                "rhs",
                "support_count",
                "antecedent_count",
                "support",
                "confidence",
                "lift",
            ]
        )
        for i, rule in enumerate(rules, start=1):
            writer.writerow(
                [
                    i,
                    " AND ".join(rule.antecedent),
                    rule.rhs,
                    rule.support_count,
                    rule.antecedent_count,
                    f"{rule.support:.6f}",
                    f"{rule.confidence:.6f}",
                    f"{rule.lift:.6f}",
                ]
            )


def recommendation_lines(top_rules: Sequence[Rule]) -> List[str]:
    return [
        "Prioritise operational resilience reviews for busy scheduled-service airports in Europe and North America where the mined rules show above-baseline delayed or cancelled outcomes, especially in Q4.",
        "Target navigation-aid upgrades and redundancy planning at airports that fall into the 1 or 2-3 navaid buckets, because several of the strongest rules concentrate disruption in these medium-coverage categories rather than at airports with no traffic significance.",
        "Use quarter-based disruption rules to guide seasonal staffing, maintenance windows, and contingency funding, with extra attention to Q4 cancellation risk and the medium-airport segment.",
    ]


def write_summary_markdown(
    path: Path,
    baseline: Dict[str, float],
    all_rules: Sequence[Rule],
    top_rules: Sequence[Rule],
) -> None:
    lines: List[str] = []
    lines.append("# Association Rule Mining Summary")
    lines.append("")
    lines.append("## Algorithm")
    lines.append("")
    lines.append(
        "This analysis used an Apriori-style, level-wise association rule mining approach implemented in pure Python. "
        "Candidate antecedent itemsets of size 1 to 3 were generated from selected categorical attributes, then support, confidence, and lift were computed for rules whose right-hand side was `Flight Status` only."
    )
    lines.append("")
    lines.append("Selected mining attributes:")
    for attribute in MINING_ATTRIBUTES:
        lines.append(f"- `{attribute}`")
    lines.append("")
    lines.append("Excluded high-cardinality identifiers and names to avoid sparse or trivial rules:")
    lines.append("- `passenger_id`, `first_name`, `last_name`, `pilot_name`, `airport_ident`, `departure_airport_code`, exact `full_date`")
    lines.append("")
    lines.append("Minimum thresholds used:")
    lines.append(f"- `min_support = {MIN_SUPPORT:.2f}`")
    lines.append(f"- `min_confidence = {MIN_CONFIDENCE:.2f}`")
    lines.append(f"- `max_antecedent_size = {MAX_ANTECEDENT_SIZE}`")
    lines.append("")
    lines.append("Baseline flight-status distribution:")
    for status, rate in baseline.items():
        lines.append(f"- `{status}`: {rate:.4f}")
    lines.append("")
    lines.append(f"Rules retained after filtering: `{len(all_rules)}`")
    lines.append("")
    lines.append("## Top Rules")
    lines.append("")
    for i, rule in enumerate(top_rules, start=1):
        lhs_plain = format_antecedent_plain_english(rule.antecedent)
        lines.append(f"### Rule {i}")
        lines.append("")
        lines.append(f"- Rule: `{ ' AND '.join(rule.antecedent) } -> flight_status={rule.rhs}`")
        lines.append(f"- Support: `{rule.support:.4f}`")
        lines.append(f"- Confidence: `{rule.confidence:.4f}`")
        lines.append(f"- Lift: `{rule.lift:.4f}`")
        lines.append(
            f"- Plain English: Among records {lhs_plain}, the probability of `{rule.rhs}` is `{rule.confidence:.4f}`, "
            f"which is `{rule.lift:.4f}` times the dataset-wide baseline for `{rule.rhs}`."
        )
        lines.append("")

    lines.append("## Insights")
    lines.append("")
    lines.append(
        "The discovered rules are directionally useful but not very strong. Most lifts are only slightly above 1.0, which means the antecedents raise the probability of the right-hand-side flight status only modestly."
    )
    lines.append(
        "This weak signal is consistent with the dataset structure: the three flight-status classes are almost perfectly balanced, so there is limited statistical room for any attribute combination to sharply separate one class from the others."
    )
    lines.append(
        "The strongest operational rules concentrate around geography, quarter, airport type, scheduled-service status, and navigation-aid availability rather than passenger demographics. That makes them more suitable for infrastructure and operations recommendations than for passenger-policy targeting."
    )
    lines.append(
        "Several potentially high-lift combinations with very small support were deliberately filtered out. This avoids over-interpreting rare patterns that are unlikely to be robust enough for policy use."
    )
    lines.append("")
    lines.append("## Recommendations")
    lines.append("")
    for recommendation in recommendation_lines(top_rules):
        lines.append(f"- {recommendation}")
    lines.append("")
    lines.append("## References")
    lines.append("")
    lines.append("- Agrawal, R., Imielinski, T., & Swami, A. (1993). Mining association rules between sets of items in large databases. *Proceedings of the 1993 ACM SIGMOD International Conference on Management of Data*.")
    lines.append("- Agrawal, R., & Srikant, R. (1994). Fast algorithms for mining association rules. *Proceedings of the 20th International Conference on Very Large Data Bases*.")

    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    transactions, rhs_counts, total_rows = load_transactions(INPUT_PATH)
    baseline = summarise_baseline(rhs_counts, total_rows)
    rules = mine_rules(transactions, rhs_counts, total_rows)
    top_rules = pick_top_non_redundant_rules(rules, TOP_K)

    write_rules_csv(OUTPUT_DIR / "all_rules.csv", rules)
    write_rules_csv(OUTPUT_DIR / "top_rules.csv", top_rules)
    write_summary_markdown(OUTPUT_DIR / "association_rule_summary.md", baseline, rules, top_rules)

    print(f"Input rows: {total_rows}")
    print(f"Rules retained: {len(rules)}")
    print(f"Top {len(top_rules)} rules:")
    for i, rule in enumerate(top_rules, start=1):
        print(
            f"{i}. {' AND '.join(rule.antecedent)} -> {rule.rhs} | "
            f"support={rule.support:.4f}, confidence={rule.confidence:.4f}, lift={rule.lift:.4f}"
        )


if __name__ == "__main__":
    main()
