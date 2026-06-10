// ScentDB: Production-Style Data Import Patterns
// =====================
// The setup.cypher file created nodes and relationships
// by writing them directly inline. That works fine for
// a small seed dataset but it does not reflect how data
// actually gets into a graph database in production.
//
// In the real world data comes from external sources:
// a PostgreSQL migration, a CSV export from a legacy system,
// an API response that needs to be transformed before loading,
// or an incremental sync that runs every night pulling new
// users and purchases from the relational database.
//
// This file demonstrates production-style import patterns
// for Neo4j: idempotent upserts using MERGE instead of CREATE,
// batch processing for large datasets, error handling for
// malformed records, validation before and after import,
// and the incremental sync pattern that keeps the graph
// in step with the PostgreSQL source of truth.
//
// The difference between CREATE and MERGE is the most
// important concept here. CREATE always makes a new node
// even if an identical one already exists. Run it twice
// and you have duplicate nodes. MERGE checks first —
// if a matching node exists it uses it, if not it creates it.
// Every production import uses MERGE. CREATE is for
// one-time setup scripts where you control the environment
// completely and know the database is empty.
// =====================

// =====================
// PART 1: IDEMPOTENT UPSERTS WITH MERGE
// =====================
// An idempotent operation produces the same result
// whether you run it once or a hundred times.
// This is critical for import scripts because imports
// fail partway through and get re-run constantly.
// A non-idempotent import creates duplicates on every retry.
// A MERGE-based import can be re-run safely at any time.

// Upsert a user — create if not exists, update if exists
MERGE (u:User {user_id: 1})
ON CREATE SET
    u.username = "scentlover1",
    u.age = 24,
    u.country = "Pakistan",
    u.collector_level = "Enthusiast",
    u.created_at = datetime(),
    u.import_source = "postgresql_sync"
ON MATCH SET
    u.last_synced_at = datetime(),
    u.import_source = "postgresql_sync";

// Upsert a fragrance
MERGE (f:Fragrance {fragrance_id: 1})
ON CREATE SET
    f.name = "Aventus",
    f.brand = "Creed",
    f.concentration = "EDP",
    f.gender = "Male",
    f.price_usd = 495,
    f.release_year = 2010,
    f.created_at = datetime(),
    f.import_source = "postgresql_sync"
ON MATCH SET
    f.price_usd = 495,
    f.last_synced_at = datetime();

// Upsert a relationship — MERGE works on relationships too
// This creates the PURCHASED relationship only if it does not
// already exist between this specific user and fragrance
MATCH (u:User {user_id: 1})
MATCH (f:Fragrance {fragrance_id: 1})
MERGE (u)-[r:PURCHASED {date: "2024-01-15"}]->(f)
ON CREATE SET
    r.price_paid = 495,
    r.bottle_ml = 100,
    r.import_source = "postgresql_sync",
    r.created_at = datetime()
ON MATCH SET
    r.last_verified_at = datetime();

// =====================
// PART 2: BATCH IMPORT PATTERN
// =====================
// When importing thousands of records the naive approach
// of running one MERGE per record is slow because each
// statement opens and closes a transaction.
// The UNWIND pattern processes a list of records in a
// single transaction — dramatically faster for bulk loads.
// In production this list would come from a parameterized
// query driven by a Python or Node.js script.

// Batch upsert all users in one transaction
WITH [
    {id: 1, username: "scentlover1", age: 24, country: "Pakistan", level: "Enthusiast"},
    {id: 2, username: "fragrancepro", age: 28, country: "UAE", level: "Expert"},
    {id: 3, username: "oud_addict", age: 31, country: "UK", level: "Collector"},
    {id: 4, username: "perfume_pk", age: 22, country: "Pakistan", level: "Beginner"},
    {id: 5, username: "scentseeker", age: 26, country: "Ireland", level: "Enthusiast"}
] AS users
UNWIND users AS user
MERGE (u:User {user_id: user.id})
ON CREATE SET
    u.username = user.username,
    u.age = user.age,
    u.country = user.country,
    u.collector_level = user.level,
    u.created_at = datetime(),
    u.import_batch = "batch_001"
ON MATCH SET
    u.last_synced_at = datetime(),
    u.import_batch = "batch_001"
RETURN COUNT(u) AS users_processed;

// Batch upsert all fragrances
WITH [
    {id: 1, name: "Aventus", brand: "Creed", concentration: "EDP", gender: "Male", price: 495, year: 2010},
    {id: 2, name: "Sauvage", brand: "Dior", concentration: "EDT", gender: "Male", price: 120, year: 2015},
    {id: 3, name: "Oud Wood", brand: "Tom Ford", concentration: "EDP", gender: "Unisex", price: 310, year: 2007},
    {id: 4, name: "Eros", brand: "Versace", concentration: "EDT", gender: "Male", price: 95, year: 2012},
    {id: 5, name: "Bleu de Chanel", brand: "Chanel", concentration: "EDP", gender: "Male", price: 185, year: 2010},
    {id: 6, name: "Miss Dior", brand: "Dior", concentration: "EDP", gender: "Female", price: 140, year: 2011},
    {id: 7, name: "Black Orchid", brand: "Tom Ford", concentration: "EDP", gender: "Unisex", price: 290, year: 2006},
    {id: 8, name: "Allure Homme", brand: "Chanel", concentration: "EDT", gender: "Male", price: 110, year: 1999}
] AS fragrances
UNWIND fragrances AS frag
MERGE (f:Fragrance {fragrance_id: frag.id})
ON CREATE SET
    f.name = frag.name,
    f.brand = frag.brand,
    f.concentration = frag.concentration,
    f.gender = frag.gender,
    f.price_usd = frag.price,
    f.release_year = frag.year,
    f.created_at = datetime(),
    f.import_batch = "batch_001"
ON MATCH SET
    f.price_usd = frag.price,
    f.last_synced_at = datetime()
RETURN COUNT(f) AS fragrances_processed;

// Batch upsert purchase relationships
WITH [
    {user_id: 1, fragrance_id: 1, date: "2024-01-15", price: 495, ml: 100},
    {user_id: 1, fragrance_id: 2, date: "2024-03-22", price: 120, ml: 100},
    {user_id: 2, fragrance_id: 3, date: "2024-02-10", price: 310, ml: 50},
    {user_id: 3, fragrance_id: 5, date: "2024-04-05", price: 185, ml: 100},
    {user_id: 4, fragrance_id: 4, date: "2024-01-30", price: 95, ml: 50},
    {user_id: 5, fragrance_id: 7, date: "2024-05-12", price: 290, ml: 100}
] AS purchases
UNWIND purchases AS purchase
MATCH (u:User {user_id: purchase.user_id})
MATCH (f:Fragrance {fragrance_id: purchase.fragrance_id})
MERGE (u)-[r:PURCHASED {date: purchase.date}]->(f)
ON CREATE SET
    r.price_paid = purchase.price,
    r.bottle_ml = purchase.ml,
    r.created_at = datetime(),
    r.import_batch = "batch_001"
ON MATCH SET
    r.last_verified_at = datetime()
RETURN COUNT(r) AS relationships_processed;

// =====================
// PART 3: DATA VALIDATION BEFORE IMPORT
// =====================
// A good import script validates the data it is about to load
// before actually loading it. Catching problems before they
// enter the graph is far cheaper than cleaning them up after.
// These checks run against the incoming data structure
// and flag anything that would cause import failures or
// create inconsistent nodes.

// Check for users that already exist in the graph
// before attempting to import a new batch
WITH [1, 2, 3, 4, 5, 99, 100] AS incoming_user_ids
UNWIND incoming_user_ids AS uid
OPTIONAL MATCH (existing:User {user_id: uid})
RETURN
    uid AS user_id,
    CASE
        WHEN existing IS NOT NULL THEN "Already exists — will update"
        ELSE "New — will create"
    END AS import_action,
    existing.username AS current_username,
    existing.last_synced_at AS last_synced;

// Check for orphaned relationships in the incoming data
// A purchase relationship referencing a user or fragrance
// that does not exist in the graph would create a dangling
// relationship — valid in Neo4j but semantically wrong here
WITH [
    {user_id: 1, fragrance_id: 1},
    {user_id: 99, fragrance_id: 1},
    {user_id: 1, fragrance_id: 999}
] AS incoming_purchases
UNWIND incoming_purchases AS purchase
OPTIONAL MATCH (u:User {user_id: purchase.user_id})
OPTIONAL MATCH (f:Fragrance {fragrance_id: purchase.fragrance_id})
RETURN
    purchase.user_id AS user_id,
    purchase.fragrance_id AS fragrance_id,
    CASE WHEN u IS NULL THEN "MISSING USER" ELSE "User OK" END AS user_status,
    CASE WHEN f IS NULL THEN "MISSING FRAGRANCE" ELSE "Fragrance OK" END AS fragrance_status,
    CASE
        WHEN u IS NULL OR f IS NULL
            THEN "SKIP — cannot create relationship, node missing"
        ELSE "OK — safe to import"
    END AS import_decision;

// =====================
// PART 4: POST IMPORT VALIDATION
// =====================
// After an import completes you need to verify it worked.
// These checks confirm node counts, relationship counts,
// and data integrity after the batch has been processed.

// Verify node counts match expectations
MATCH (u:User) WITH COUNT(u) AS user_count
MATCH (f:Fragrance) WITH COUNT(f) AS fragrance_count, user_count
MATCH (b:Brand) WITH COUNT(b) AS brand_count, fragrance_count, user_count
MATCH (n:Note) WITH COUNT(n) AS note_count, brand_count, fragrance_count, user_count
RETURN
    user_count AS users,
    fragrance_count AS fragrances,
    brand_count AS brands,
    note_count AS notes;

// Verify relationship counts
MATCH ()-[r:PURCHASED]->() WITH COUNT(r) AS purchases
MATCH ()-[r:RATED]->() WITH COUNT(r) AS ratings, purchases
MATCH ()-[r:WISHLISTED]->() WITH COUNT(r) AS wishlists, ratings, purchases
MATCH ()-[r:SIMILAR_TO]->() WITH COUNT(r) AS similarities, wishlists, ratings, purchases
MATCH ()-[r:HAS_NOTE]->() WITH COUNT(r) AS note_maps, similarities, wishlists, ratings, purchases
MATCH ()-[r:MADE_BY]->() WITH COUNT(r) AS brand_links, note_maps, similarities, wishlists, ratings, purchases
RETURN
    purchases,
    ratings,
    wishlists,
    similarities AS fragrance_similarities,
    note_maps,
    brand_links;

// Check for any nodes that were created without all required properties
// These indicate a partial import failure
MATCH (u:User)
WHERE u.username IS NULL
   OR u.country IS NULL
   OR u.collector_level IS NULL
RETURN
    u.user_id AS incomplete_user_id,
    u.username AS username,
    "Missing required properties" AS issue;

MATCH (f:Fragrance)
WHERE f.name IS NULL
   OR f.brand IS NULL
   OR f.price_usd IS NULL
RETURN
    f.fragrance_id AS incomplete_fragrance_id,
    f.name AS name,
    "Missing required properties" AS issue;

// Check for duplicate nodes that should be unique
// Duplicates indicate MERGE was bypassed somehow
MATCH (u:User)
WITH u.user_id AS uid, COUNT(*) AS count
WHERE count > 1
RETURN uid AS duplicate_user_id, count AS occurrences
ORDER BY occurrences DESC;

MATCH (f:Fragrance)
WITH f.fragrance_id AS fid, COUNT(*) AS count
WHERE count > 1
RETURN fid AS duplicate_fragrance_id, count AS occurrences
ORDER BY occurrences DESC;

// =====================
// PART 5: INCREMENTAL SYNC PATTERN
// =====================
// A full import re-processes every record every time.
// That is fine for small datasets but wasteful at scale.
// The incremental sync pattern only processes records
// that have changed since the last sync ran.
// The last_synced_at timestamp on each node is the mechanism —
// records modified in PostgreSQL after that timestamp
// are the ones that need to be re-synced to Neo4j.

// Find nodes that have not been synced in the last 24 hours
// In production this query drives the list of records
// to pull from PostgreSQL for the next sync batch
MATCH (u:User)
WHERE u.last_synced_at < datetime() - duration({hours: 24})
   OR u.last_synced_at IS NULL
RETURN
    u.user_id,
    u.username,
    u.last_synced_at,
    "Needs sync" AS status
ORDER BY u.last_synced_at ASC;

MATCH (f:Fragrance)
WHERE f.last_synced_at < datetime() - duration({hours: 24})
   OR f.last_synced_at IS NULL
RETURN
    f.fragrance_id,
    f.name,
    f.last_synced_at,
    "Needs sync" AS status
ORDER BY f.last_synced_at ASC;

// =====================
// PART 6: IMPORT AUDIT LOG
// =====================
// Every import should leave a trace. The audit node pattern
// creates a lightweight log of what was imported, when,
// how many records were processed, and whether it succeeded.
// This is the Neo4j equivalent of the audit_log table
// we built in PostgreSQL — same discipline, different tool.

MERGE (log:ImportLog {
    import_id: "import_" + toString(timestamp())
})
ON CREATE SET
    log.import_batch = "batch_001",
    log.import_type = "full_sync",
    log.source_system = "PostgreSQL ScentDB",
    log.started_at = datetime(),
    log.records_attempted = 5,
    log.records_succeeded = 5,
    log.records_failed = 0,
    log.status = "completed",
    log.completed_at = datetime(),
    log.run_by = "system_scheduler";

// View recent import logs
MATCH (log:ImportLog)
RETURN
    log.import_batch,
    log.import_type,
    log.started_at,
    log.records_attempted,
    log.records_succeeded,
    log.records_failed,
    log.status
ORDER BY log.started_at DESC
LIMIT 10;