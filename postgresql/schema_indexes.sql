-- ScentDB: Indexing Strategy
-- Indexes are created to optimize the most frequent query patterns
-- in a fragrance analytics platform

-- =====================
-- WHY INDEXES MATTER HERE
-- =====================
-- Without indexes, PostgreSQL does a full table scan on every query.
-- As the dataset grows (thousands of users, millions of wear sessions),
-- unindexed queries become the bottleneck. These indexes are chosen
-- based on the actual query patterns in queries.sql and queries_advanced.sql

-- =====================
-- USERS TABLE
-- =====================

-- Email is queried constantly (login, lookup, deduplication)
CREATE INDEX idx_users_email ON users(email);

-- Country filtering for regional analytics
CREATE INDEX idx_users_country ON users(country);

-- =====================
-- FRAGRANCES TABLE
-- =====================

-- Brand lookups are the most common join in the system
CREATE INDEX idx_fragrances_brand ON fragrances(brand_id);

-- Filtering by concentration (EDP/EDT/Parfum) and gender target
CREATE INDEX idx_fragrances_concentration ON fragrances(concentration);
CREATE INDEX idx_fragrances_gender ON fragrances(gender_target);

-- Price range filtering for recommendation engine
CREATE INDEX idx_fragrances_price ON fragrances(price_usd);

-- =====================
-- PURCHASES TABLE
-- =====================

-- User purchase history is queried constantly
CREATE INDEX idx_purchases_user ON purchases(user_id);

-- Fragrance-level purchase analytics
CREATE INDEX idx_purchases_fragrance ON purchases(fragrance_id);

-- Date-based trend analysis (monthly revenue, time series)
CREATE INDEX idx_purchases_date ON purchases(purchase_date);

-- Composite index: user + date together (running totals, user timelines)
CREATE INDEX idx_purchases_user_date ON purchases(user_id, purchase_date);

-- =====================
-- RATINGS TABLE
-- =====================

-- User rating history
CREATE INDEX idx_ratings_user ON ratings(user_id);

-- Fragrance average rating queries
CREATE INDEX idx_ratings_fragrance ON ratings(fragrance_id);

-- Score filtering (find all ratings above 8, etc.)
CREATE INDEX idx_ratings_score ON ratings(score);

-- Composite: user + fragrance (checking if a user already rated something)
CREATE INDEX idx_ratings_user_fragrance ON ratings(user_id, fragrance_id);

-- =====================
-- FRAGRANCE NOTE MAP
-- =====================

-- Note lookup per fragrance (used heavily in recommendation engine)
CREATE INDEX idx_note_map_fragrance ON fragrance_note_map(fragrance_id);

-- Fragrance lookup per note (find all fragrances sharing a note)
CREATE INDEX idx_note_map_note ON fragrance_note_map(note_id);

-- =====================
-- WISHLISTS TABLE
-- =====================

-- User wishlist retrieval
CREATE INDEX idx_wishlists_user ON wishlists(user_id);

-- Priority-based sorting
CREATE INDEX idx_wishlists_priority ON wishlists(priority);

-- =====================
-- AUDIT LOG
-- =====================

-- Filter audit log by table and action type
CREATE INDEX idx_audit_table ON audit_log(table_name);
CREATE INDEX idx_audit_action ON audit_log(action);
CREATE INDEX idx_audit_user ON audit_log(performed_by);
CREATE INDEX idx_audit_time ON audit_log(performed_at);

-- =====================
-- PERFORMANCE ANALYSIS
-- =====================

-- Use EXPLAIN ANALYZE to verify index usage
-- Run these after inserting seed data to see the difference

-- Without index hint (PostgreSQL decides):
EXPLAIN ANALYZE
SELECT * FROM purchases
WHERE user_id = 1
ORDER BY purchase_date;

-- Check index usage across the whole database
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan AS times_used,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- Check table sizes vs index sizes
SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size(tablename::text)) AS total_size,
    pg_size_pretty(pg_relation_size(tablename::text)) AS table_size,
    pg_size_pretty(pg_total_relation_size(tablename::text) - pg_relation_size(tablename::text)) AS index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(tablename::text) DESC;