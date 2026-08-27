# Booking Messaging & Rewards — Analytics Pipeline

A portfolio project simulating a Data Engineer role on Booking.com's Messaging &
Rewards team: a medallion-architecture analytics pipeline built with **dbt** and
**DuckDB** on top of a synthetic hotel chat/booking dataset, feeding a "Why We
Lose Bookings" dashboard.

## Stack

- **DuckDB** — embedded warehouse (`warehouse/booking.duckdb`, gitignored — rebuild with `dbt run`)
- **dbt-duckdb** — data modeling, testing, documentation
- **Parquet** (`data/*.parquet`) — synthetic raw source files, read directly by dbt sources via `read_parquet()`
- **Static HTML/JS dashboard** (`dashboard_prototype/`) — consumes the marts layer for the exec-facing report

## Data architecture

Medallion layout, each layer a dbt model directory:

```
data/*.parquet  →  models/staging/  →  models/intermediate/  →  models/marts/  →  dashboard_prototype/
   (raw)              (1:1 views)         (joins, business          (consumption-        (static site)
                                             logic)                   ready tables)
```

| Layer | Location | Materialization | Purpose |
|---|---|---|---|
| Staging | `models/staging/` | view | 1:1 views over raw source Parquet, light renaming/casting only |
| Intermediate | `models/intermediate/` | table | Joins, business logic, conversation-journey and risk-scoring transformations |
| Marts | `models/marts/` | table | Consumption-ready tables powering the dashboard |

### Sources (raw data)

Registered in `models/staging/_staging__sources.yml`, pointed at `data/*.parquet`.
Grain and columns are documented there; see also [README_mock_data.md](README_mock_data.md)
for how the synthetic dataset is generated.

- `dim_users` — one row per guest
- `dim_hosts` — one row per property host
- `dim_properties` — one row per listing
- `fact_bookings` — one row per booking (user → property → host)
- `dim_conversations` — one row per chat thread tied to a booking
- `fact_chat_messages` — one row per individual chat message

### Staging models

One view per source table (`stg_dim_users`, `stg_fact_bookings`, etc.) — renaming/
casting only, no business logic.

### Intermediate models (`models/intermediate/`)

- **`int_booking_cancellation_risk`** — one row per confirmed booking; rule-based
  composite `cancellation_risk_score` (0–1) from conversation/message signals
  (intent, sentiment, CSAT, escalation, response speed). Flags the top risk decile.
- **`int_conversation_log`** — one row per chat message, sequenced within its
  conversation (`message_seq`, first/last flags, time since previous message).
- **`int_conversation_journeys`** — collapses the message-grain log to one row per
  conversation: full event/sentiment journey strings, opening/closing sentiment,
  escalation and delayed-reply counts. Shared base for every mart below.
- **`int_at_risk_conversations`** / **`int_at_risk_conversation_concerns`** —
  drill-down into the top-risk-decile segment and its dominant concerns.

### Marts (`models/marts/`)

Each mart is consumption-ready and maps to a specific piece of the dashboard:

| Mart | Grain | Powers |
|---|---|---|
| `mart_booking_loss_events` | 1 row per conversation (trailing 12mo) | Master fact table: `journey_stage` (WHERE it went wrong) + `event_pattern` (WHAT happened, mutually exclusive) |
| `mart_loss_by_month_pattern` | month × channel × loyalty_tier × event_pattern | Month × event-pattern impact heatmap |
| `mart_loss_by_stage` | month × channel × loyalty_tier × journey_stage | "Where in the journey we lose bookings" table + revenue-lost hero stats |
| `mart_complaint_cohort` | month × channel × loyalty_tier × intent_category | Top-5 complaints / everyday questions, loyalty-tier breakdown |
| `mart_price_quintile_risk` | price quintile (1–5) | "Booking value doesn't predict who cancels, but predicts what it costs" chart |
| `mart_unanswered_opening_monthly` | month | Monthly cohort trend for the "unanswered opening message" pattern — the strongest single driver found (1.58x baseline cancellation rate) |

Full column-level docs live in `models/marts/_marts__models.yml` and are browsable
via `dbt docs generate && dbt docs serve`.

### Dashboard (`dashboard_prototype/`)

Static HTML/JS prototype consuming the marts above:

- `dashboard_prototype.html` — main "Why We Lose Bookings" report (KPIs, loss-by-stage table, month × pattern heatmap, complaint cohorts, price-quintile chart)
- `dashboard_prototype_page2.html` — customer-journey / Sankey drill-down view

This started as a separate repo ([booking-dashboard-prototype](https://github.com/jameslimpin1/booking-dashboard-prototype),
published via GitHub Pages); these copies are the actively developed versions.

### Analysis (`analysis/`)

Exec-summary writeups and CSV extracts used to prep the dashboard content — see
[analysis/README.md](analysis/README.md) for the underlying findings
(cancellation-risk scoring, stage-loss analysis, top concerns).

## Setup

```bash
cd booking_project
python3 -m venv .venv && source .venv/bin/activate
pip install dbt-duckdb
```

`profiles.yml` targets `warehouse/booking.duckdb` (profile `booking_messaging_rewards`, target `dev`).

## Running the pipeline

```bash
dbt run                      # build all models
dbt test                     # run schema/data tests
dbt run --select staging     # build just the staging layer
dbt run --select marts       # build just the marts layer
dbt docs generate && dbt docs serve   # browse full column-level documentation
```

> DuckDB allows only one writer at a time — close any other connection (e.g. a
> VSCode DuckDB extension) holding `warehouse/booking.duckdb` before running
> `dbt`, or open read-only: `duckdb -readonly warehouse/booking.duckdb`.

All paths in `_staging__sources.yml` are relative to the project root — run
`dbt`/`duckdb` commands from `booking_project/`, not a subdirectory.

## Roadmap

- [x] Staging + intermediate layers
- [x] Marts layer powering the dashboard
- [x] Dashboard prototype (loss-by-stage, month × pattern heatmap, complaint cohorts, price-quintile risk)
- [ ] Schema tests (`unique`/`not_null`/`relationships`) across staging models
- [ ] Sankey customer-journey view (in progress, see `dashboard_prototype_page2.html`)
