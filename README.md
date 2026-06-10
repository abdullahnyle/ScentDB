# ScentDB — Fragrance Analytics Platform

A multi-model database system built across PostgreSQL, MongoDB,
and Neo4j that models a fragrance retail platform end to end.
The project covers the full stack of database engineering:
schema design, normalization, transactions, stored procedures,
triggers, indexing, partitioning, materialized views, NoSQL
document modeling, graph-based recommendation logic, and a
complete analytical layer built on top of all three systems.

Each database was chosen for a specific reason. PostgreSQL
owns the structured transactional core. MongoDB handles
variable behavioral data that does not fit a fixed schema.
Neo4j powers the recommendation engine where relationship
traversal is the primary operation. The architecture document
in docs/ explains every decision in detail.

---

## Tech Stack

- **PostgreSQL** — relational core, analytics, reporting views
- **MongoDB** — behavioral data, market trends, aggregation pipelines
- **Neo4j** — graph recommendations, community analysis, PageRank
- **SQL** — analytical frameworks built from scratch
- **Cypher** — graph queries and import patterns
- **JavaScript** — MongoDB queries, aggregation pipelines, schema validation

---

## Repository Structure
ScentDB/
├── postgresql/
│   ├── schema.sql                Core relational schema (7 tables, BCNF)
│   ├── schema_advanced.sql       Notes, wishlists, audit log, triggers, views
│   ├── schema_indexes.sql        14 indexes with rationale
│   ├── schema_normalization.sql  1NF → BCNF walkthrough with violation examples
│   ├── seed.sql                  Seed data across all tables
│   ├── queries.sql               Core analytical queries
│   ├── queries_advanced.sql      Window functions, stored procedure, views
│   ├── transactions.sql          ACID transactions, isolation levels, deadlock prevention
│   ├── advanced_functions.sql    LTV, fragrance scoring, demand forecasting, triggers
│   ├── data_quality.sql          Six-dimension data quality framework
│   ├── reporting_views.sql       8 Power BI-ready views
│   ├── materialized_views.sql    Pre-computed snapshots with concurrent refresh
│   └── partitioning.sql          Range, list, and hash partitioning patterns
├── mongodb/
│   ├── documents.js              Wear sessions and preference logs
│   ├── queries.js                Core queries and aggregations
│   ├── market_trends.js          Regional market data across 6 countries
│   ├── analytics_pipeline.js     Complex multi-stage pipelines
│   ├── user_behavior.js          Behavioral tracking collection
│   ├── aggregation_pipelines.js  Advanced pipelines with $lookup and $unwind
│   └── schema_validation.js      JSON schema validation for all 3 collections
├── neo4j/
│   ├── setup.cypher              Node and relationship creation
│   ├── queries.cypher            Lookups and basic recommendations
│   ├── advanced_queries.cypher   Churn detection, basket analysis, influencer scoring
│   ├── graph_algorithms.cypher   Centrality, PageRank approximation, shortest path
│   └── data_import.cypher        Production import with MERGE, validation, sync patterns
├── analytics/
│   ├── rfm_analysis.sql          Five-stage RFM segmentation
│   ├── cohort_analysis.sql       Six-component cohort retention framework
│   ├── retention_analysis.sql    Churn scoring, health index, reactivation probability
│   ├── basket_analysis.sql       Support, confidence, lift, affinity scoring
│   ├── price_analysis.sql        Pricing strategy, elasticity, discount simulation
│   ├── product_analytics.sql     Funnel analysis, catalog matrix, engagement scoring
│   └── geographic_analytics.sql  Regional performance, market penetration, expansion scoring
├── docs/
│   ├── architecture.md           Full system design and decision rationale
│   └── er_diagram.md             Entity relationship map across all three systems
└── README.md
---

## PostgreSQL Layer

The relational layer is the system of record. It stores
every transactional entity — users, brands, fragrances,
purchases, ratings, wishlists — in a fully normalized
schema that satisfies BCNF across all tables.

Beyond the schema, the PostgreSQL layer includes four
stored functions (user lifetime value, fragrance composite
scoring, demand forecasting, price sensitivity estimation),
three triggers (purchase audit logging, automatic wishlist
cleanup on purchase, suspicious pattern detection), fourteen
indexes tuned to the actual query patterns in the system,
three materialized views with concurrent refresh support,
and a full table partitioning strategy across range, list,
and hash partition types.

The reporting views layer sits on top of everything and
provides eight clean pre-joined views designed to connect
directly to Power BI without requiring any transformation
in Power Query.

---

## MongoDB Layer

MongoDB owns the data that does not fit a relational schema.

Wear sessions capture behavioral data per fragrance wear
event — occasion, weather, mood, duration, compliments
received. The structure varies per document because not
every session captures every field. Preference logs record
what users say they like versus what behavioral data shows
they actually reach for. Market trends store regional
fragrance industry data from six countries, with variable
structure across documents as different reports track
different metrics.

Seven multi-stage aggregation pipelines extract analytical
value from this data: fragrance performance by weather
condition, unified user taste profile construction via
$lookup joins across collections, time series analysis on
wear sessions, occasion intelligence, preference-to-behavior
gap analysis, regional market opportunity scoring, and
emerging trend signal detection across markets.

Schema validation rules enforce data quality at the
collection level — required fields, value ranges, and
enumerated constraints — without sacrificing the structural
flexibility that makes MongoDB the right choice here.

---

## Neo4j Layer

The graph layer powers the recommendation engine and
community analysis. Five node types — User, Fragrance,
Note, Brand, ImportLog — connect through seven relationship
types: PURCHASED, RATED, WISHLISTED, SIMILAR_TASTE,
HAS_NOTE, MADE_BY, SIMILAR_TO.

The recommendation engine runs three traversal patterns.
Collaborative filtering finds what similar users own that
this user does not. Content-based filtering finds fragrances
sharing notes with things a user rated highly. Similarity
chaining follows direct SIMILAR_TO edges from loved fragrances.

The advanced query layer covers churn detection through
purchase gap analysis, market basket analysis, influencer
identification, price sensitivity mapping with tier-appropriate
recommendations, cross-selling opportunities, and geographic
taste pattern analysis.

The graph algorithms file implements degree centrality,
betweenness centrality approximation, shortest path
traversal, clustering coefficient analysis, and a PageRank
approximation that scores fragrances by network centrality.

The import layer documents production patterns: MERGE-based
idempotent upserts, batch processing with UNWIND, pre-import
validation, post-import verification, incremental sync
tracking, and an ImportLog audit node pattern.

---

## Analytics Layer

Seven standalone analytical files sit outside the database
folders because they draw on all three systems rather than
belonging to any one of them.

**RFM Analysis** — Recency, Frequency, Monetary segmentation
across five stages from raw metric calculation through
actionable CRM recommendations per customer segment.

**Cohort Analysis** — Monthly acquisition cohort retention
tracking with revenue analysis, behavioral pattern breakdown,
early churn signal detection, and lifetime value projection.

**Retention Analysis** — Churn risk scoring relative to each
customer's personal purchase rhythm rather than a fixed
cutoff. Includes a customer health index, reactivation
probability scoring for churned customers, a retention
curve by purchase sequence number, and an intervention
timing calendar with messaging angles per customer.

**Basket Analysis** — Support, confidence, and lift
calculation for every fragrance pair. Brand affinity
analysis, sequential purchase pattern tracking, and a
composite affinity score table ready to feed a live
recommendation engine.

**Price Analysis** — Distribution across price tiers,
conversion rates by tier, price versus rating correlation,
brand pricing strategy classification, discount impact
simulation across three scenarios with documented assumptions,
price anchoring effect analysis, and per-fragrance
pricing recommendations.

**Product Analytics** — Discovery-to-purchase funnel,
BCG-style catalog performance matrix, composite user
engagement scoring, new product launch velocity tracking,
and cross-sell and upsell opportunity identification.

**Geographic Analytics** — Country-level performance,
regional fragrance preferences, price sensitivity by market,
market penetration estimates connecting PostgreSQL behavioral
data with MongoDB market sizing figures, seasonal patterns
by hemisphere, and geographic expansion opportunity scoring.

---

## Data Quality

A dedicated data quality framework covers all six dimensions:
completeness, validity, uniqueness, consistency, referential
integrity, and freshness. It includes per-dimension checks,
a master scorecard that rolls all six into a single pass/fail
status, and is designed to run as a health check before any
significant analytical work begins.

---

## Docs

**docs/architecture.md** explains why each database was
chosen, how the schema decisions were made, what each
analytical framework does and why it exists, and how the
three systems connect through shared entity identifiers.

**docs/er_diagram.md** maps every entity, attribute,
relationship, constraint, and trigger across all three
systems including cross-system identifier links and
analytics layer dependencies.

---

## Getting Started

**PostgreSQL**
```sql
-- Create the database
CREATE DATABASE scentdb;

-- Run in order
\i postgresql/schema.sql
\i postgresql/schema_advanced.sql
\i postgresql/seed.sql
\i postgresql/schema_indexes.sql

-- Then run any query or analytics file
\i postgresql/queries.sql
\i analytics/rfm_analysis.sql
```

**MongoDB**
```javascript
// Run in MongoDB Shell or Compass
// Load each file in order
load("mongodb/documents.js")
load("mongodb/market_trends.js")
load("mongodb/queries.js")
load("mongodb/schema_validation.js")
```

**Neo4j**
```cypher
// Run in Neo4j Browser in order
// 1. setup.cypher
// 2. data_import.cypher
// 3. queries.cypher
// 4. advanced_queries.cypher
// 5. graph_algorithms.cypher
```

---

## Power BI Connection

Connect Power BI Desktop to PostgreSQL (localhost, scentdb)
and select only the `vw_` prefixed views. Each view is
pre-joined and pre-calculated — no transformation needed
in Power Query. The reporting_views.sql file includes a
full connection guide mapping each view to its report page.

---

## Built With

PostgreSQL 16 · MongoDB 7 · Neo4j 5 · VS Code
