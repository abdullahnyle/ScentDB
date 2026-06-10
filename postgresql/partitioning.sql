-- ScentDB: Table Partitioning Strategy
-- =====================
-- Partitioning is one of those topics that separates someone
-- who has worked with data at scale from someone who has only
-- ever queried small datasets. The concept is straightforward:
-- instead of storing all your data in one giant table, you
-- split it across multiple physical partitions based on some
-- logical boundary — usually a date range or a category.
--
-- Why does this matter? Imagine the purchases table five years
-- from now with ten million rows. A query asking for last
-- month's revenue still has to scan the entire table to find
-- the rows it needs unless the table is partitioned by date.
-- With date partitioning, PostgreSQL knows immediately that
-- last month's data lives in one specific partition and goes
-- there directly. The other nine million rows are never touched.
-- That difference — scanning 80,000 rows instead of 10,000,000
-- — is the difference between a dashboard that loads in a
-- second and one that times out.
--
-- This file demonstrates three partitioning strategies:
-- range partitioning on dates for the purchases table,
-- list partitioning on categories for the fragrances table,
-- and hash partitioning for even distribution of ratings.
-- Each strategy fits a different access pattern and knowing
-- which to use when is the kind of judgment that comes from
-- thinking about data as a system rather than a collection
-- of tables to query.
-- =====================

-- =====================
-- STRATEGY 1: RANGE PARTITIONING ON PURCHASES
-- =====================
-- The purchases table is queried almost exclusively by date.
-- Revenue reports filter by month or quarter. Cohort analysis
-- groups by acquisition month. Retention analysis looks at
-- recent purchases versus older ones. Range partitioning
-- by purchase_date means every single one of those queries
-- touches only the partitions it actually needs.

-- Create the partitioned parent table
-- Note: this is a demonstration schema — in production you
-- would migrate data from the existing purchases table into
-- this partitioned version using pg_dump and a carefully
-- planned migration window.

CREATE TABLE IF NOT EXISTS purchases_partitioned (
    purchase_id     SERIAL,
    user_id         INT NOT NULL,
    fragrance_id    INT NOT NULL,
    purchase_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    price_paid      DECIMAL(10,2) NOT NULL,
    bottle_size_ml  INT,
    PRIMARY KEY (purchase_id, purchase_date)
) PARTITION BY RANGE (purchase_date);

-- Create partitions for each quarter of 2024
-- In production you would automate this with a cron job
-- that creates the next quarter's partition before it is needed.
-- Forgetting to create a partition causes inserts to fail —
-- that is the most common operational mistake with this pattern.

CREATE TABLE IF NOT EXISTS purchases_2024_q1
    PARTITION OF purchases_partitioned
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');

CREATE TABLE IF NOT EXISTS purchases_2024_q2
    PARTITION OF purchases_partitioned
    FOR VALUES FROM ('2024-04-01') TO ('2024-07-01');

CREATE TABLE IF NOT EXISTS purchases_2024_q3
    PARTITION OF purchases_partitioned
    FOR VALUES FROM ('2024-07-01') TO ('2024-10-01');

CREATE TABLE IF NOT EXISTS purchases_2024_q4
    PARTITION OF purchases_partitioned
    FOR VALUES FROM ('2024-10-01') TO ('2025-01-01');

-- 2025 partitions ready in advance
CREATE TABLE IF NOT EXISTS purchases_2025_q1
    PARTITION OF purchases_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2025-04-01');

CREATE TABLE IF NOT EXISTS purchases_2025_q2
    PARTITION OF purchases_partitioned
    FOR VALUES FROM ('2025-04-01') TO ('2025-07-01');

CREATE TABLE IF NOT EXISTS purchases_2025_q3
    PARTITION OF purchases_partitioned
    FOR VALUES FROM ('2025-07-01') TO ('2025-10-01');

CREATE TABLE IF NOT EXISTS purchases_2025_q4
    PARTITION OF purchases_partitioned
    FOR VALUES FROM ('2025-10-01') TO ('2026-01-01');

-- Create indexes on each partition
-- Indexes on partitioned tables need to be created on each
-- partition individually or on the parent (PostgreSQL 11+
-- supports global indexes on the parent table)
CREATE INDEX IF NOT EXISTS idx_purchases_part_user_2024_q1
    ON purchases_2024_q1(user_id);

CREATE INDEX IF NOT EXISTS idx_purchases_part_user_2024_q2
    ON purchases_2024_q2(user_id);

CREATE INDEX IF NOT EXISTS idx_purchases_part_user_2024_q3
    ON purchases_2024_q3(user_id);

CREATE INDEX IF NOT EXISTS idx_purchases_part_user_2024_q4
    ON purchases_2024_q4(user_id);

-- =====================
-- STRATEGY 2: LIST PARTITIONING ON FRAGRANCES
-- =====================
-- The fragrances table gets queried very differently depending
-- on whether you are looking at gender-targeted products,
-- concentration types, or price tiers. List partitioning
-- by gender_target means queries that filter by Male, Female,
-- or Unisex only scan the relevant partition.
-- This is a smaller table than purchases so the performance
-- gain is modest now, but the pattern is worth demonstrating
-- because it shows you understand that partitioning strategy
-- should match query patterns, not just table size.

CREATE TABLE IF NOT EXISTS fragrances_partitioned (
    fragrance_id    SERIAL,
    name            VARCHAR(100) NOT NULL,
    brand_id        INT NOT NULL,
    concentration   VARCHAR(50),
    release_year    INT,
    price_usd       DECIMAL(10,2),
    gender_target   VARCHAR(20) NOT NULL,
    PRIMARY KEY (fragrance_id, gender_target)
) PARTITION BY LIST (gender_target);

CREATE TABLE IF NOT EXISTS fragrances_male
    PARTITION OF fragrances_partitioned
    FOR VALUES IN ('Male');

CREATE TABLE IF NOT EXISTS fragrances_female
    PARTITION OF fragrances_partitioned
    FOR VALUES IN ('Female');

CREATE TABLE IF NOT EXISTS fragrances_unisex
    PARTITION OF fragrances_partitioned
    FOR VALUES IN ('Unisex');

-- Default partition catches anything that does not match
-- the explicit list values — prevents insert failures if
-- a new gender_target value is introduced later
CREATE TABLE IF NOT EXISTS fragrances_other
    PARTITION OF fragrances_partitioned
    DEFAULT;

-- =====================
-- STRATEGY 3: HASH PARTITIONING ON RATINGS
-- =====================
-- Ratings do not have an obvious range or list dimension
-- to partition on. User IDs are distributed evenly and
-- there is no natural category boundary to split on.
-- Hash partitioning solves this by distributing rows
-- evenly across a fixed number of partitions based on
-- a hash of the user_id. This keeps partition sizes
-- balanced and prevents the hot partition problem
-- where one partition grows much larger than others.

CREATE TABLE IF NOT EXISTS ratings_partitioned (
    rating_id       SERIAL,
    user_id         INT NOT NULL,
    fragrance_id    INT NOT NULL,
    score           INT CHECK (score BETWEEN 1 AND 10),
    review_text     TEXT,
    rated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (rating_id, user_id)
) PARTITION BY HASH (user_id);

-- Four hash partitions distribute ratings evenly
-- The modulus is the total number of partitions (4)
-- The remainder identifies which partition each row goes to
CREATE TABLE IF NOT EXISTS ratings_hash_0
    PARTITION OF ratings_partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);

CREATE TABLE IF NOT EXISTS ratings_hash_1
    PARTITION OF ratings_partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);

CREATE TABLE IF NOT EXISTS ratings_hash_2
    PARTITION OF ratings_partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 2);

CREATE TABLE IF NOT EXISTS ratings_hash_3
    PARTITION OF ratings_partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 3);

-- =====================
-- PARTITION PRUNING VERIFICATION
-- =====================
-- Partition pruning is the mechanism that makes partitioning
-- valuable. When PostgreSQL sees a WHERE clause that matches
-- the partition key, it prunes (skips) all partitions that
-- cannot possibly contain matching rows.
-- EXPLAIN shows you whether pruning is actually happening.

-- This query should only scan purchases_2024_q1
-- You will see "Partitions: purchases_2024_q1" in the plan
EXPLAIN
SELECT *
FROM purchases_partitioned
WHERE purchase_date BETWEEN '2024-01-01' AND '2024-03-31';

-- This one should scan purchases_2024_q2 and q3 only
EXPLAIN
SELECT COUNT(*), SUM(price_paid)
FROM purchases_partitioned
WHERE purchase_date BETWEEN '2024-04-01' AND '2024-09-30';

-- This one scans all partitions because there is no date filter
-- Shows the cost of unfiltered queries on partitioned tables
EXPLAIN
SELECT COUNT(*) FROM purchases_partitioned;

-- =====================
-- PARTITION MAINTENANCE
-- =====================
-- Partitioned tables need ongoing maintenance that regular
-- tables do not. The most important task is creating future
-- partitions before they are needed. The second is archiving
-- or dropping old partitions when the data is no longer needed.

-- Check the size of each partition
SELECT
    schemaname,
    tablename AS partition_name,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename))
        AS total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename))
        AS table_size
FROM pg_tables
WHERE tablename LIKE 'purchases_20%'
   OR tablename LIKE 'fragrances_%'
   OR tablename LIKE 'ratings_hash_%'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Count rows in each purchase partition
SELECT
    tableoid::regclass AS partition,
    COUNT(*) AS row_count
FROM purchases_partitioned
GROUP BY tableoid
ORDER BY partition;

-- Archive old partitions by detaching them from the parent
-- This keeps the data accessible as a standalone table
-- without it being included in queries against the parent.
-- Detach 2024 Q1 as an example of the archival pattern:
-- ALTER TABLE purchases_partitioned
--     DETACH PARTITION purchases_2024_q1;

-- Drop a partition when the data is no longer needed at all
-- This is permanent — make sure you have a backup first.
-- DROP TABLE purchases_2024_q1;

-- =====================
-- WHEN NOT TO PARTITION
-- =====================
-- Partitioning adds operational complexity and is only worth
-- it when the performance benefit is real. The general rules:
--
-- DO partition when:
-- 1. The table has more than a few million rows
-- 2. Most queries filter on the partition key
-- 3. You regularly need to drop or archive old data
-- 4. Vacuum and autovacuum are becoming performance problems
--
-- DO NOT partition when:
-- 1. The table is small (under ~1 million rows)
-- 2. Queries do not filter on a natural partition key
-- 3. You need foreign keys that reference the table
--    (partitioned tables have limited FK support)
-- 4. You need global unique indexes across all partitions
--
-- ScentDB at its current seed data size does not need
-- partitioning. This file demonstrates the pattern so you
-- can apply it when the data grows to a size where it matters.
-- That is the honest answer and it is the one worth giving
-- in an interview when someone asks about your partitioning
-- strategy — knowing when NOT to use a tool is as important
-- as knowing how to use it.

-- =====================
-- MIGRATION PATTERN
-- =====================
-- How would you migrate the existing purchases table to the
-- partitioned version without downtime? This is the question
-- that comes up in every production database conversation.

-- Step 1: Create the partitioned table (done above)
-- Step 2: Copy data in batches to avoid locking
-- INSERT INTO purchases_partitioned
-- SELECT * FROM purchases
-- WHERE purchase_date >= '2024-01-01'
-- AND purchase_date < '2024-04-01';
-- (repeat for each partition)

-- Step 3: Verify row counts match
SELECT
    'purchases (original)' AS source,
    COUNT(*) AS row_count
FROM purchases
UNION ALL
SELECT
    'purchases_partitioned (migrated)',
    COUNT(*)
FROM purchases_partitioned;

-- Step 4: In a transaction, rename tables to swap them
-- BEGIN;
-- ALTER TABLE purchases RENAME TO purchases_old;
-- ALTER TABLE purchases_partitioned RENAME TO purchases;
-- COMMIT;

-- Step 5: Verify application queries work against the new table
-- Step 6: Drop purchases_old after a validation period
-- DROP TABLE purchases_old;