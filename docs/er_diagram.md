# ScentDB: Entity Relationship Map

## Overview

This document maps every entity in the ScentDB system,
their attributes, and the relationships between them.
It covers all three database systems — PostgreSQL, MongoDB,
and Neo4j — and documents how entities connect across
system boundaries through shared identifiers.

---

## PostgreSQL Entities

### brands

The root entity for the product catalog. Every fragrance
belongs to exactly one brand. Brands do not belong to any
other entity — they are the top of the ownership hierarchy.

```
brands
├── brand_id        SERIAL PRIMARY KEY
├── name            VARCHAR(100) NOT NULL
├── country         VARCHAR(100)
└── founded_year    INT
```

Relationships:
- One brand has many fragrances (one-to-many)
- A fragrance cannot exist without a brand

---

### fragrances

The central product entity. Almost every other entity in
the system connects to fragrances in some way — users
purchase them, rate them, wishlist them, and wear them.
Notes map to them. Brands own them.

```
fragrances
├── fragrance_id    SERIAL PRIMARY KEY
├── name            VARCHAR(100) NOT NULL
├── brand_id        INT FK → brands.brand_id
├── concentration   VARCHAR(50)
├── release_year    INT
├── price_usd       DECIMAL(10,2)
└── gender_target   VARCHAR(20)
```

Relationships:
- Many fragrances belong to one brand (many-to-one)
- One fragrance has many purchases (one-to-many)
- One fragrance has many ratings (one-to-many)
- One fragrance appears on many wishlists (one-to-many)
- One fragrance has many notes via fragrance_note_map (many-to-many)

---

### users

The customer entity. Users are the actors in the system —
they drive every behavioral event that the analytics layer
measures.

```
users
├── user_id         SERIAL PRIMARY KEY
├── username        VARCHAR(100) NOT NULL
├── email           VARCHAR(150) UNIQUE NOT NULL
├── age             INT
├── country         VARCHAR(100)
└── joined_date     DATE DEFAULT CURRENT_DATE
```

Relationships:
- One user makes many purchases (one-to-many)
- One user writes many ratings (one-to-many)
- One user has many wishlist items (one-to-many)
- One user generates many audit log entries (one-to-many)

---

### purchases

The primary transaction entity. Every purchase event is
a single row connecting a user to a fragrance at a specific
point in time. The trigger on this table fires on every
insert and creates an audit log entry automatically.

```
purchases
├── purchase_id     SERIAL PRIMARY KEY
├── user_id         INT FK → users.user_id
├── fragrance_id    INT FK → fragrances.fragrance_id
├── purchase_date   DATE DEFAULT CURRENT_DATE
├── price_paid      DECIMAL(10,2)
└── bottle_size_ml  INT
```

Relationships:
- Many purchases belong to one user (many-to-one)
- Many purchases are for one fragrance (many-to-one)
- One purchase may trigger one audit log entry (via trigger)
- One purchase may delete one wishlist item (via trigger)

---

### ratings

The feedback entity. A rating connects a user to a fragrance
with a score and an optional review. The business rule is
that ratings should only exist for fragrances the user has
purchased — the data quality framework checks this constraint
and flags violations.

```
ratings
├── rating_id       SERIAL PRIMARY KEY
├── user_id         INT FK → users.user_id
├── fragrance_id    INT FK → fragrances.fragrance_id
├── score           INT CHECK (score BETWEEN 1 AND 10)
├── review_text     TEXT
└── rated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
```

Relationships:
- Many ratings belong to one user (many-to-one)
- Many ratings are for one fragrance (many-to-one)
- One rating update may create one rating_history record (via trigger)

---

### wishlists

The intent entity. A wishlist item signals that a user
wants a fragrance they do not yet own. The trigger on
purchases automatically removes the corresponding wishlist
item when a user completes a purchase — keeping expressed
intent aligned with actual ownership.

```
wishlists
├── wishlist_id     SERIAL PRIMARY KEY
├── user_id         INT FK → users.user_id
├── fragrance_id    INT FK → fragrances.fragrance_id
├── added_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
└── priority        INT CHECK (priority BETWEEN 1 AND 5)
```

Relationships:
- Many wishlist items belong to one user (many-to-one)
- Many wishlist items reference one fragrance (many-to-one)

---

### notes

The ingredient entity. A note is a single fragrance
ingredient — Bergamot, Oud, Sandalwood. Notes are stored
as independent entities rather than as strings attached to
fragrances because they need to be queried independently.
Finding all fragrances that contain Bergamot requires
notes to be rows, not comma-separated strings.

```
notes
├── note_id         SERIAL PRIMARY KEY
├── name            VARCHAR(100) NOT NULL
├── category        VARCHAR(50)
└── family          VARCHAR(50)
```

Relationships:
- One note appears in many fragrances via fragrance_note_map (many-to-many)

---

### fragrance_note_map

The junction table that resolves the many-to-many
relationship between fragrances and notes. A fragrance
has multiple notes. A note appears in multiple fragrances.
This table holds the connection between them along with
the note_type attribute that indicates whether this note
is a top, middle, or base note in this specific fragrance.

```
fragrance_note_map
├── map_id          SERIAL PRIMARY KEY
├── fragrance_id    INT FK → fragrances.fragrance_id
├── note_id         INT FK → notes.note_id
└── note_type       VARCHAR(20)
```

Relationships:
- Many map entries reference one fragrance (many-to-one)
- Many map entries reference one note (many-to-one)

---

### audit_log

The system event entity. Every significant data event
in the system creates an audit log entry — purchases,
suspicious patterns, automatic wishlist cleanup, rating
changes. The audit log is append-only by convention.
Nothing should ever be deleted from it.

```
audit_log
├── log_id          SERIAL PRIMARY KEY
├── table_name      VARCHAR(50)
├── action          VARCHAR(20)
├── performed_by    INT FK → users.user_id
├── performed_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
└── details         TEXT
```

Relationships:
- Many log entries reference one user (many-to-one)
- Log entries are created by triggers, not by application code directly

---

### rating_history

The change tracking entity. Every time a user updates a
rating score the old and new values are preserved here.
This entity exists because understanding how satisfaction
evolves post-purchase is analytically valuable — a user
who raises their score over time is developing genuine
brand loyalty. One who lowers it is signaling a problem.

```
rating_history
├── history_id      SERIAL PRIMARY KEY
├── rating_id       INT
├── user_id         INT
├── fragrance_id    INT
├── old_score       INT
├── new_score       INT
├── changed_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
└── change_reason   TEXT
```

Relationships:
- Many history records reference one rating (many-to-one)
- Created automatically by the rating change trigger

---

## PostgreSQL Relationship Map

```
brands (1) ──────────────────────── (many) fragrances
                                            │
                            ┌───────────────┼───────────────┐
                            │               │               │
                      (many)│         (many)│         (many)│
                        purchases        ratings        wishlists
                            │               │               │
                      (many)│         (many)│         (many)│
                            └───────────────┼───────────────┘
                                            │
                                        users (1)

fragrances (many) ── fragrance_note_map ── (many) notes

purchases ──trigger──► audit_log
purchases ──trigger──► wishlists (delete)
ratings   ──trigger──► rating_history
```

---

## Normalization Summary

Every table in the PostgreSQL schema satisfies BCNF.

**brands:** all non-key attributes (name, country, founded_year)
depend only on brand_id. No transitive dependencies.

**fragrances:** brand data lives in brands, not repeated here.
brand_id is the only reference to brand information.

**users:** all user attributes depend only on user_id.
No derived or redundant columns.

**purchases:** price_paid, purchase_date, and bottle_size_ml
all describe the purchase event itself, not the user or
the fragrance. No partial or transitive dependencies.

**ratings:** score and review_text describe the rating event.
They do not describe the user or the fragrance beyond
the foreign key references.

**fragrance_note_map:** note_type describes this specific
fragrance-note pairing. It does not describe the note
in general or the fragrance in general.

**notes:** category and family describe the note itself,
not how it is used in any specific fragrance.

---

## MongoDB Collections

MongoDB does not use foreign keys or enforced relationships.
Relationships between MongoDB documents and PostgreSQL
entities are maintained by convention through shared
identifier values — user_id and fragrance_id.

### wear_sessions

A behavioral event document. One document per wear session.
The structure varies by how much data the user chose to record
for that session — the required fields are the minimum
that makes a document analytically useful.

```
wear_sessions document
├── user_id               INT  (matches PostgreSQL users.user_id)
├── username              STRING
├── fragrance_id          INT  (matches PostgreSQL fragrances.fragrance_id)
├── fragrance_name        STRING
├── date                  STRING  (YYYY-MM-DD)
├── occasion              STRING  (enum: Wedding, Office, Date Night...)
│
├── (optional fields — present only when recorded)
├── mood                  STRING
├── weather               STRING  (enum: Hot, Warm, Mild, Cool, Cold, Rainy, Humid)
├── temperature_celsius   INT
├── duration_hours        NUMBER
├── compliments_received  INT
├── notes                 STRING
└── extra_data            OBJECT  (catches anything that does not fit above)
```

Cross-system link: user_id → PostgreSQL users.user_id
Cross-system link: fragrance_id → PostgreSQL fragrances.fragrance_id

---

### preference_logs

A stated preference document. One document per user
preference capture event. Records what users say they
like as distinct from what behavioral data shows they
actually do. The gap between these two collections is
analytically significant.

```
preference_logs document
├── user_id                   INT  (matches PostgreSQL users.user_id)
├── username                  STRING
├── logged_at                 STRING  (YYYY-MM-DD)
│
├── (optional preference dimensions)
├── favorite_notes            ARRAY of STRING
├── disliked_notes            ARRAY of STRING
├── preferred_occasions       ARRAY of STRING
├── preferred_concentration   STRING  (enum: EDT, EDP, Parfum, EDC, Solid)
├── budget_range_usd          OBJECT
│   ├── min                   NUMBER
│   └── max                   NUMBER
├── current_collection_size   INT
└── extra_data                OBJECT
```

Cross-system link: user_id → PostgreSQL users.user_id

---

### market_trends

A regional market data document. One document per country
per reporting period. Structure varies by report source —
some include sustainability metrics, some include digital
influence data, some include seasonal effect breakdowns.
This variability is the reason this data lives in MongoDB
rather than PostgreSQL.

```
market_trends document
├── region                        STRING  (enum: Middle East, South Asia...)
├── country                       STRING
├── period                        STRING  (Q1-2024 format)
├── season                        STRING
├── currency                      STRING
├── market_size_usd_millions      NUMBER
├── yoy_growth_percent            NUMBER
├── avg_spend_per_customer_usd    NUMBER
├── top_selling_categories        ARRAY of OBJECT
│   ├── category                  STRING
│   └── market_share_percent      NUMBER
├── consumer_demographics         OBJECT
├── most_popular_fragrance_families  ARRAY of STRING
├── seasonal_notes                STRING
├── emerging_trends               ARRAY of STRING
├── top_retail_channels           OBJECT
├── data_quality                  STRING  (enum: verified, estimated...)
└── source                        STRING

(some documents also include)
├── climate_impact                OBJECT
├── digital_influence             OBJECT
├── sustainability_metrics        OBJECT
└── ramadan_effect                OBJECT
```

Cross-system link: country → used as join key in
geographic_analytics.sql to connect PostgreSQL
behavioral data with MongoDB market sizing data

---

## Neo4j Graph Schema

Neo4j stores entities as nodes and relationships as edges.
Properties live on both nodes and edges. The graph schema
mirrors the PostgreSQL entity structure but is optimized
for traversal rather than storage.

### Node Types

```
(:User)
├── user_id           INT  (matches PostgreSQL users.user_id)
├── username          STRING
├── age               INT
├── country           STRING
├── collector_level   STRING  (Beginner, Enthusiast, Expert, Collector)
├── created_at        DATETIME
└── last_synced_at    DATETIME

(:Fragrance)
├── fragrance_id      INT  (matches PostgreSQL fragrances.fragrance_id)
├── name              STRING
├── brand             STRING
├── concentration     STRING
├── gender            STRING
├── price_usd         FLOAT
├── release_year      INT
├── created_at        DATETIME
└── last_synced_at    DATETIME

(:Note)
├── name              STRING
├── family            STRING
└── layer             STRING  (Top, Middle, Base)

(:Brand)
├── name              STRING
├── country           STRING
└── tier              STRING  (Ultra Luxury, Luxury, Designer, Accessible)

(:ImportLog)
├── import_id         STRING
├── import_batch      STRING
├── import_type       STRING
├── source_system     STRING
├── started_at        DATETIME
├── records_attempted INT
├── records_succeeded INT
├── records_failed    INT
├── status            STRING
└── completed_at      DATETIME
```

---

### Relationship Types

```
(:User)-[:PURCHASED {
    date        STRING,
    price_paid  FLOAT,
    bottle_ml   INT
}]->(:Fragrance)

(:User)-[:RATED {
    score       INT,
    review      STRING
}]->(:Fragrance)

(:User)-[:WISHLISTED {
    priority    INT,
    added_date  STRING
}]->(:Fragrance)

(:User)-[:SIMILAR_TASTE {
    reason          STRING,
    overlap_score   FLOAT
}]->(:User)

(:Fragrance)-[:HAS_NOTE {
    layer           STRING
}]->(:Note)

(:Fragrance)-[:MADE_BY]->(:Brand)

(:Fragrance)-[:SIMILAR_TO {
    reason              STRING,
    similarity_score    FLOAT
}]->(:Fragrance)
```

---

### Graph Traversal Patterns

The relationships above enable four core traversal patterns
that the query files exploit.

**Direct lookup:** User → PURCHASED → Fragrance
What has this user bought? Single hop, O(1) per user.

**Collaborative filtering:** User → SIMILAR_TASTE → User
→ PURCHASED → Fragrance (minus what first user owns)
What do similar users own that this user does not?
Two hops. Classic collaborative filtering pattern.

**Content-based filtering:** User → RATED (score ≥ 8)
→ Fragrance → HAS_NOTE → Note ← HAS_NOTE ← Fragrance (not yet owned)
What fragrances share notes with things this user loved?
Four hops. Content-based recommendation pattern.

**Similarity chain:** User → RATED → Fragrance
→ SIMILAR_TO → Fragrance (not yet owned)
What is directly similar to things this user rated highly?
Three hops. Fastest recommendation path.

---

## Cross-System Entity Map

The three database systems share entity identifiers
to enable cross-system analysis.

```
Entity          PostgreSQL              MongoDB                     Neo4j
────────────────────────────────────────────────────────────────────────────
User            users.user_id           wear_sessions.user_id       (:User).user_id
                                        preference_logs.user_id

Fragrance       fragrances              wear_sessions               (:Fragrance)
                .fragrance_id           .fragrance_id               .fragrance_id

Brand           brands.brand_id         (not stored)                (:Brand).name
                                                                    (by name reference)

Note            notes.note_id           (not stored)                (:Note).name
                                                                    (by name reference)

Market Region   (not stored)            market_trends.country       (not stored)
                referenced by name in geographic_analytics.sql
```

---

## Analytics Layer Dependencies

```
rfm_analysis.sql
└── purchases, users

cohort_analysis.sql
└── purchases, users, fragrances

retention_analysis.sql
└── purchases, users, ratings, wishlists

basket_analysis.sql
└── purchases, fragrances, brands, ratings

price_analysis.sql
└── fragrances, brands, purchases, ratings, wishlists

product_analytics.sql
└── fragrances, brands, purchases, ratings, wishlists

geographic_analytics.sql
└── users, purchases, ratings, wishlists
└── market_trends (MongoDB — referenced by country name)

kpi_dashboard.sql
└── vw_daily_kpis, vw_monthly_summary (reporting views)
```

---

## Constraint Summary

```
PostgreSQL Constraints
──────────────────────
users.email                   UNIQUE
ratings.score                 CHECK (1 ≤ score ≤ 10)
wishlists.priority            CHECK (1 ≤ priority ≤ 5)
purchases.price_paid          DECIMAL(10,2) — type constraint
All FK columns                REFERENCES with CASCADE behavior

PostgreSQL Triggers
───────────────────
after_purchase_insert         → logs to audit_log
after_purchase_clean_wishlist → deletes from wishlists
check_suspicious_purchases    → logs to audit_log if count > 3
track_rating_changes          → inserts into rating_history

MongoDB Validation (validationLevel: moderate)
───────────────────────────────────────────────
wear_sessions.user_id         required, int, min 1
wear_sessions.date            required, string, YYYY-MM-DD pattern
wear_sessions.occasion        required, enum of approved values
wear_sessions.weather         optional, enum if present
wear_sessions.temperature     optional, int, -20 to 55 if present
wear_sessions.duration        optional, 0 to 24 if present
preference_logs.user_id       required, int, min 1
preference_logs.logged_at     required, string, YYYY-MM-DD pattern
preference_logs.concentration optional, enum if present
market_trends.region          required, enum of world regions
market_trends.period          required, string, Q[1-4]-YYYY pattern
market_trends.market_size     required, number, min 0
market_trends.yoy_growth      required, number, -100 to 200

Neo4j (no enforced constraints — maintained by MERGE pattern)
──────────────────────────────────────────────────────────────
User.user_id                  unique by MERGE convention
Fragrance.fragrance_id        unique by MERGE convention
Duplicate detection queries in data_import.cypher
verify uniqueness after every import batch
```