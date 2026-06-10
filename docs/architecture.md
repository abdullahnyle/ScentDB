# ScentDB: Architecture & Design Decisions

## What This Project Is

ScentDB is a fragrance analytics platform built across three
database systems. It models a real retail operation — users
discovering, purchasing, rating, and building collections of
fragrances — and uses each database for the specific problems
it is genuinely best at solving.

The system is not multi-database for the sake of looking
impressive. Each choice has a reason and that reason connects
directly to the nature of the data being stored and the
queries being run against it.

---

## Why Three Databases

The fragrance domain has three fundamentally different kinds
of data that behave differently, grow differently, and get
queried differently.

The first kind is structured transactional data. Users,
brands, fragrances, purchases, ratings. These have fixed
schemas, strict relationships between them, and need ACID
guarantees — if a purchase is recorded, the audit log entry
must be recorded too, or neither should be. This is exactly
what relational databases were designed for.

The second kind is variable behavioral data. When someone
wears a fragrance they might record the occasion, the weather,
their mood, the number of compliments they received, and
notes about how it performed. But not every session has all
of these fields. Some have extras that others do not. Forcing
this into a relational schema means either dozens of nullable
columns or a separate table per attribute type — both
approaches that get ugly fast. A document store handles this
naturally because each document carries exactly the fields
that make sense for it.

The third kind is relationship data. The question of what to
recommend to a user based on what similar users bought, or
which fragrances share enough notes to be meaningfully
similar, is fundamentally a graph traversal problem. In a
relational database this requires multi-level self-joins that
get exponentially more expensive as the network grows. In a
graph database the same traversal follows edges directly and
scales gracefully.

---

## PostgreSQL — The Relational Core

PostgreSQL owns the structured, transactional heart of the
system. Every entity that has a fixed schema and strict
relationships with other entities lives here.

### Schema Design

The schema normalizes to BCNF across seven core tables.
Brands own brand data. Fragrances reference brands by foreign
key. Notes are stored independently and mapped to fragrances
through a junction table rather than as a comma-separated
string. This separation means you can query every fragrance
that contains Bergamot without parsing strings — you just
join through the map table.

The advanced schema adds wishlists, an audit log, and a
rating history table. The audit log is populated automatically
by triggers rather than application code, which means it
cannot be bypassed even if a developer forgets to add the
logging call. The rating history table tracks every score
change so you can see if a user revised their opinion of a
fragrance over time — the kind of signal that matters for
understanding how satisfaction evolves post-purchase.

### Stored Procedures and Functions

Four analytical functions encapsulate the business logic
that would otherwise be duplicated across queries.

`calculate_user_ltv` computes lifetime value per customer
including projected annual spend based on their purchase
velocity. `calculate_fragrance_score` produces a composite
performance score for each fragrance combining ratings,
purchase volume, and wishlist demand. `forecast_demand`
projects future purchase volume using linear extrapolation
from historical purchase rates. `estimate_price_sensitivity`
calculates a price-per-rating-point metric that reveals
whether customers feel each fragrance justifies its price.

Encapsulating this logic in functions means it is calculated
consistently everywhere it is used. A KPI dashboard and a
one-off analyst query get the same number because they call
the same function.

### Triggers

Three triggers automate behavior that would otherwise depend
on application code getting it right every time.

The purchase audit trigger fires after every insert on the
purchases table and logs the event to audit_log automatically.
The wishlist cleanup trigger removes a fragrance from a
user's wishlist the moment they purchase it, keeping the
wishlist accurate without requiring a separate API call.
The suspicious purchase trigger flags any user who has
purchased the same fragrance more than three times, which
could indicate a data entry error or reselling behavior
worth reviewing.

### Indexing Strategy

Fourteen indexes cover the most frequent query patterns.
The most important are composite indexes on purchases
(user_id, purchase_date) and ratings (user_id, fragrance_id),
which are the two most common join conditions in the
analytical queries. Single-column indexes on foreign keys
ensure that joins never trigger full table scans.

The fragrance_note_map table gets indexes on both fragrance_id
and note_id because it is traversed in both directions — find
all notes for a fragrance and find all fragrances containing
a note are both common queries.

### Materialized Views

Three materialized views pre-compute the heaviest aggregations
in the system: the fragrance daily snapshot, the customer
summary, and the brand performance snapshot. Each joins four
or five tables and calculates a dozen metrics per row.

Running these queries fresh on every dashboard load would be
acceptable at the current data scale but painful at ten
million rows. The materialized views store the results
physically and refresh nightly. Dashboard queries against
them return in milliseconds regardless of how much data
sits in the underlying tables.

The views are designed to refresh concurrently — users can
query the previous version while the new one builds in the
background, which means the dashboard never goes blank during
a refresh.

### Partitioning

The purchases table is partitioned by date into quarterly
ranges. The fragrances table is partitioned by gender_target
using list partitioning. The ratings table uses hash
partitioning on user_id for even distribution.

At the current data scale partitioning is not necessary.
The file documents the pattern so it is ready to apply when
the data grows to a size where it matters — and demonstrates
the judgment to know the difference between when a technique
is needed and when it is premature optimization.

### Reporting Views

Eight views prefixed with vw_ form the interface between
the database and Power BI. They are designed to load cleanly
into Power BI without requiring transformation in Power Query.
Relationships between views connect on fragrance_id, user_id,
and brand_id. Each view is named after the report page it
feeds so the connection between data model and presentation
layer is explicit.

---

## MongoDB — Behavioral and Market Data

MongoDB owns data that does not fit a fixed schema and does
not need transactional guarantees across multiple collections.

### Wear Sessions

The wear sessions collection is the clearest example of why
a document store is the right choice here. A user recording
a wear session might capture weather, temperature, mood,
occasion, duration, compliments, outfit color, location, and
notes about performance — or they might capture only the
fragrance name and the date. The fields vary by user, by
occasion, and by how engaged that particular user is with
tracking their fragrance behavior.

In PostgreSQL this would require either a table with twenty
nullable columns — most of them empty for most rows — or an
entity-attribute-value pattern that makes querying painful.
In MongoDB each document carries exactly the fields it has
and nothing else. The schema validation layer defines which
fields are required and which are optional, so the flexibility
does not come at the cost of data quality.

### Preference Logs

Preference logs capture what users say they like as distinct
from what they actually do. A user might state that they
prefer Oud and dislike Vanilla, but their wear session data
shows them reaching for fresh citrus fragrances consistently.
That gap between stated preference and observed behavior is
one of the most interesting signals in consumer analytics.

Keeping stated preferences in a separate collection from
behavioral data makes the gap analysis explicit — you are
deliberately joining two different sources rather than
accidentally mixing them in the same table.

### Market Trends

The market trends collection stores regional fragrance market
data sourced from industry reports. This data is structurally
different from the transactional data in PostgreSQL in two
ways. First, the schema evolves as new metrics become
available — a report from 2024 might track sustainability
metrics that 2022 reports did not include. Second, it is
reference data rather than transactional data — it informs
analysis but does not record system events.

The geographic analytics SQL file in the analytics folder
references this collection explicitly, noting where the
MongoDB figures feed into the PostgreSQL-side calculations.
In a production unified data warehouse both sources would
be joined directly. Here the connection is documented
clearly so the two-system nature of the analysis is
transparent rather than hidden.

### Schema Validation

All three collections have JSON schema validation rules
applied at the database level. Required fields are enforced,
value ranges are checked, enumerated fields are constrained
to approved values, and date strings are validated against
a format pattern.

The validation level is set to moderate with a warn action
during development — documents that violate the schema are
accepted but logged. In production this would switch to
strict with an error action so invalid documents are
rejected at the database level rather than silently polluting
the collection.

### Aggregation Pipelines

Seven multi-stage aggregation pipelines handle the complex
analytical questions that live in MongoDB's data. The
fragrance performance by weather pipeline calculates a
performance score per fragrance per weather condition using
a weighted combination of average duration, compliments, and
session count. The user taste profile builder joins wear
sessions with preference logs using a $lookup stage to
construct a unified profile document per user. The emerging
trend signal detector unwinds trend arrays across market
documents and scores each trend by how many markets are
reporting it independently.

---

## Neo4j — The Recommendation Graph

Neo4j owns the relationship-heavy data where the connections
between entities are as important as the entities themselves.

### Why a Graph Database Here

The recommendation engine's core question is: given what
this user has purchased and rated highly, what should we
show them next? In PostgreSQL this requires joining purchases
to ratings to fragrance_note_map to find shared notes, then
filtering out things the user already owns, then ranking by
some combination of note overlap and similarity score. The
query is long, fragile, and gets slower as the dataset grows
because each join multiplies the intermediate result set.

In Neo4j the same question is a pattern match: find users
who are similar to this one, find what they bought, exclude
what this user already owns, return what remains. The graph
traversal follows edges rather than scanning rows. It is
faster, simpler to read, and scales naturally because the
cost of traversal grows with the depth of the query rather
than the size of the dataset.

### Node Types

Five node types model the entities in the system.

User nodes carry identity and behavioral attributes including
collector level — a derived classification from Beginner
through Expert that reflects how deeply a user engages with
fragrance collecting.

Fragrance nodes carry the product attributes that matter
for recommendations: concentration, gender target, price,
and release year. The price in particular feeds the
price-sensitive recommendation query that avoids recommending
a $500 bottle to someone whose purchase history tops out
at $100.

Note nodes represent individual fragrance ingredients.
Bergamot, Oud, Sandalwood, Rose — each is a node, and the
connections between fragrances through shared notes form
the backbone of the note-based recommendation path.

Brand nodes carry tier classification — Ultra Luxury, Luxury,
Designer, Accessible — which enables brand-affinity queries
that respect price positioning. A user who collects Ultra
Luxury fragrances gets different cross-sell recommendations
than one mixing Designer and Accessible.

ImportLog nodes form the audit trail for the data import
process, recording what was loaded, when, and whether it
succeeded.

### Relationship Types

Seven relationship types connect the nodes.

PURCHASED carries the date, price paid, and bottle size.
RATED carries the score and review text. WISHLISTED carries
priority and date added. These three mirror the PostgreSQL
schema and are kept in sync through the incremental import
pattern documented in data_import.cypher.

HAS_NOTE connects fragrances to their ingredient notes with
a layer property indicating top, middle, or base note.
MADE_BY connects fragrances to brands. SIMILAR_TO connects
fragrances that share enough characteristics to be
meaningfully comparable, carrying a similarity score and a
human-readable reason. SIMILAR_TASTE connects users whose
purchase and rating histories overlap significantly.

### Query Layers

The Neo4j query files are organized in three layers of
increasing complexity.

The basic queries in queries.cypher handle direct lookups:
what has a user purchased, what is on their wishlist, which
fragrances has a user both bought and rated highly.

The advanced queries in advanced_queries.cypher handle
business intelligence problems: churn detection through
purchase gap analysis, market basket analysis finding which
fragrances are most commonly purchased together, influencer
identification finding users whose ratings predict others'
wishlist additions, and price sensitivity mapping that
segments users by their price tolerance and generates
tier-appropriate recommendations.

The graph algorithms in graph_algorithms.cypher implement
network analysis techniques: degree centrality finding the
most connected nodes, betweenness centrality finding bridge
nodes that connect otherwise separate communities, shortest
path traversal showing how any two fragrances are connected
through the network, and a PageRank approximation that scores
fragrances by their centrality in the taste graph.

The import patterns in data_import.cypher document production
practices: MERGE-based idempotent upserts, batch processing
with UNWIND, pre-import validation, post-import verification,
and the incremental sync pattern that keeps the graph
current with the PostgreSQL source of truth.

---

## The Analytics Layer

The analytics folder sits outside the three database folders
deliberately. It represents the analytical work that draws
on all three systems rather than belonging to any single one.

### RFM Analysis

RFM — Recency, Frequency, Monetary — is one of the most
widely used customer segmentation frameworks in retail
analytics. The implementation here walks through five stages:
raw metric calculation, NTILE-based scoring, segment
classification, segment-level summary, and actionable
marketing recommendations per customer. Each stage builds
on the previous one and the final output connects directly
to a CRM system — specific customers, specific actions,
specific timing.

### Cohort Analysis

The cohort analysis tracks what percentage of each monthly
acquisition cohort returned to purchase in subsequent months.
Six components cover the full picture: the raw cohort
assignments, the retention grid, revenue by cohort, cohort
behavior patterns, early churn signals, and lifetime value
projection. The retention grid is the centerpiece —
a matrix where rows are acquisition months and columns are
months since first purchase, showing exactly when each
cohort starts to drop off.

### Retention Analysis

The retention analysis goes deeper than cohort retention
by calculating churn risk relative to each customer's
personal purchase rhythm rather than a fixed cutoff.
A customer who normally buys every 30 days is at risk
at day 45. One who normally buys every 180 days is not.
The framework produces a customer health index, a
reactivation probability score for already-churned customers,
a retention curve showing drop-off by purchase sequence
number, and a concrete intervention calendar with recommended
contact dates and messaging angles per customer.

### Basket Analysis

Market basket analysis calculates support, confidence, and
lift for every pair of fragrances in the purchase history.
Support measures how often a pair appears together.
Confidence measures the directional probability: given A,
how likely is B? Lift normalizes confidence against the
base rate of B to show whether the relationship is stronger
than chance. The output is a ranked affinity score table
ready to feed a recommendation engine.

### Price Analysis

The price analysis covers distribution across price tiers,
conversion rates by tier, price versus rating correlation,
brand pricing strategy classification, discount impact
simulation across three scenarios, price anchoring effect
analysis, and an optimal price point recommendation for
each fragrance. The discount simulation is worth noting
specifically — it models three levels of discount depth
against three assumptions about volume uplift and shows
which scenario maximizes revenue per tier, with clear
documentation of the assumptions so the analysis is
transparent about its limitations.

### Product Analytics

The product analytics file builds a discovery-to-purchase
funnel, a BCG-style catalog performance matrix, a composite
user engagement score, new product launch tracking, and
cross-sell and upsell opportunity identification. The funnel
analysis connects directly to the conversion rate question
every product team asks: where are we losing people between
interest and purchase?

### Geographic Analytics

The geographic analytics file ties the PostgreSQL behavioral
data to the MongoDB market trends data explicitly, noting
where the two sources connect and what each contributes.
Country-level performance, regional fragrance preferences,
price sensitivity by country, market penetration estimates,
seasonal patterns by hemisphere, high-value customer
identification relative to regional averages, and geographic
expansion opportunity scoring complete the picture.

### Data Quality Framework

The data quality framework covers all six dimensions of data
quality: completeness, validity, uniqueness, consistency,
referential integrity, and freshness. It includes a master
scorecard that rolls all six dimensions into a single
pass/fail status per dimension, designed to run as a health
check before any significant analytical work begins.

### Reporting Views

Eight Power BI-ready views form the presentation layer.
They are designed so a Power BI developer can connect to
the database, select the vw_ prefixed views, and build
a full dashboard without writing a single line of SQL
or doing any transformation in Power Query. The connection
guide in the file documents which view feeds which report
page and how relationships between views should be set.

---

## How the Three Systems Connect

The three databases are not isolated. They share a common
set of entity identifiers — user_id and fragrance_id appear
in all three systems and serve as the join keys when analysis
crosses system boundaries.

PostgreSQL is the system of record. User IDs and fragrance IDs
are generated there and flow outward to MongoDB and Neo4j
through the import process. When a new user is created in
PostgreSQL, the incremental sync picks up the new record
and creates the corresponding User node in Neo4j. When a
new purchase is recorded, the same sync creates the PURCHASED
relationship in Neo4j and the wear session capability becomes
available for that purchase in MongoDB.

The geographic analytics file shows the cross-system pattern
most explicitly — PostgreSQL behavioral data on the left side
of the query, MongoDB market size figures referenced by
country name on the right, with clear documentation of where
a production unified warehouse would make this a direct join
rather than a reference.

---

## File Structure
ScentDB/
├── postgresql/
│   ├── schema.sql                 Core relational schema
│   ├── schema_advanced.sql        Notes, wishlists, audit log, views, procedure, trigger
│   ├── schema_indexes.sql         Indexing strategy with rationale
│   ├── schema_normalization.sql   1NF through BCNF with violation examples
│   ├── seed.sql                   Base seed data
│   ├── queries.sql                Core analytical queries
│   ├── queries_advanced.sql       Views, stored procedure, window functions
│   ├── transactions.sql           ACID transactions, isolation levels, deadlock prevention
│   ├── advanced_functions.sql     LTV, fragrance scoring, demand forecasting, triggers
│   ├── data_quality.sql           Six-dimension data quality framework
│   ├── reporting_views.sql        Power BI-ready view layer
│   ├── materialized_views.sql     Pre-computed snapshots with refresh strategy
│   └── partitioning.sql           Range, list, and hash partitioning patterns
├── mongodb/
│   ├── documents.js               Wear sessions and preference logs seed data
│   ├── queries.js                 Core aggregation queries
│   ├── market_trends.js           Regional market data across six countries
│   ├── analytics_pipeline.js      Seven complex multi-stage pipelines
│   ├── user_behavior.js           Behavioral tracking collection
│   ├── aggregation_pipelines.js   Advanced pipelines with $lookup and $unwind
│   └── schema_validation.js       JSON schema validation for all three collections
├── neo4j/
│   ├── setup.cypher               Node and relationship creation
│   ├── queries.cypher             Basic lookups and recommendations
│   ├── advanced_queries.cypher    Churn, basket analysis, influencer identification
│   ├── graph_algorithms.cypher    Centrality, PageRank, shortest path
│   └── data_import.cypher        Production import patterns with MERGE and validation
├── analytics/
│   ├── rfm_analysis.sql           Five-stage RFM segmentation
│   ├── cohort_analysis.sql        Six-component cohort retention framework
│   ├── retention_analysis.sql     Churn scoring, health index, reactivation probability
│   ├── basket_analysis.sql        Support, confidence, lift, affinity scoring
│   ├── price_analysis.sql         Pricing strategy, elasticity, discount simulation
│   ├── product_analytics.sql      Funnel, catalog matrix, engagement scoring
│   └── geographic_analytics.sql   Regional performance, market penetration, expansion scoring
├── docs/
│   ├── architecture.md            This file
│   └── er_diagram.md              Entity relationship map
└── README.md
---

## What This Project Demonstrates

Built across three database systems with a full analytics
layer on top, ScentDB covers the technical ground that
matters for a business analytics career: schema design and
normalization, query optimization, stored procedures and
triggers, transaction management, NoSQL document modeling,
graph traversal and recommendation logic, and the full
suite of analytical frameworks — RFM, cohort analysis,
retention modeling, basket analysis, and price analytics —
that drive decisions in real retail and e-commerce operations.

The Power BI reporting view layer connects the data model
directly to the visualization tool that sits in the Tier 1
skill stack. The data quality framework reflects the
unglamorous but essential discipline of treating data as
a system with failure modes rather than a collection of
tables to query. The partitioning and materialized view
files demonstrate awareness of performance at scale even
when the current dataset does not require it.

The project is built the way a developer would actually
build it — with intentional decisions, documented rationale,
and a structure that someone reading the repository cold
can navigate without a guided tour.