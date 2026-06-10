-- ScentDB: Materialized Views
-- =====================
-- A regular view runs its underlying query every single time
-- you query it. For simple views that is fine. For the kind
-- of analytical queries we built in the reporting_views file
-- — multi-table joins, window functions, aggregations across
-- the entire purchase history — running that query fresh on
-- every dashboard load is wasteful and slow.
--
-- A materialized view solves this by storing the query result
-- physically on disk like a table. Queries against it return
-- instantly because the heavy computation already happened.
-- The tradeoff is staleness — the materialized view does not
-- update automatically when the underlying data changes.
-- You refresh it on a schedule that matches how fresh the
-- data needs to be. A daily executive dashboard can refresh
-- overnight. A real-time fraud detection view cannot use
-- materialization at all. Knowing which is which is part
-- of designing a data system that actually works in practice.
--
-- For a portfolio this file demonstrates something specific
-- that most junior candidates miss entirely: awareness of
-- query performance at scale. Anyone can write a correct
-- query. Fewer people think about what happens when that
-- query runs against ten million rows instead of fifty.
-- Materialized views are one of the first tools a data
-- engineer reaches for when a dashboard starts to slow down.
-- Showing you know they exist and why puts you ahead of
-- most people at your stage.
-- =====================

-- =====================
-- MATERIALIZED VIEW 1: FRAGRANCE DAILY SNAPSHOT
-- =====================
-- This is the heaviest query in the system — it joins five
-- tables and calculates aggregates across all purchases,
-- ratings, and wishlists for every fragrance in the catalog.
-- Running it fresh on every Power BI refresh would be painful
-- at scale. Materializing it and refreshing it nightly means
-- the dashboard always loads instantly.

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_fragrance_daily_snapshot AS
SELECT
    f.fragrance_id,
    f.name AS fragrance,
    b.name AS brand,
    b.country AS brand_country,
    f.concentration,
    f.gender_target,
    f.price_usd,
    f.release_year,
    -- Sales performance
    COUNT(DISTINCT p.purchase_id) AS total_purchases,
    COUNT(DISTINCT p.user_id) AS unique_buyers,
    ROUND(COALESCE(SUM(p.price_paid), 0), 2) AS total_revenue,
    ROUND(COALESCE(AVG(p.price_paid), 0), 2) AS avg_price_paid,
    -- Rating performance
    COUNT(DISTINCT r.rating_id) AS total_reviews,
    ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_rating,
    COALESCE(MAX(r.score), 0) AS highest_rating,
    COALESCE(MIN(r.score), 0) AS lowest_rating,
    -- Demand signals
    COUNT(DISTINCT w.wishlist_id) AS wishlist_count,
    -- Conversion rate from wishlist to purchase
    ROUND(
        COUNT(DISTINCT p.purchase_id)::DECIMAL /
        NULLIF(COUNT(DISTINCT w.wishlist_id), 0) * 100,
        1
    ) AS wishlist_conversion_rate,
    -- Note profile
    STRING_AGG(DISTINCT n.name, ', ' ORDER BY n.name)
        AS fragrance_notes,
    -- Composite performance score
    ROUND(
        COALESCE(AVG(r.score), 5) * 0.35 +
        COUNT(DISTINCT p.purchase_id) * 0.35 +
        COUNT(DISTINCT w.wishlist_id) * 0.20 +
        COUNT(DISTINCT r.rating_id) * 0.10,
        3
    ) AS performance_score,
    -- Price tier
    CASE
        WHEN f.price_usd < 100  THEN 'Accessible'
        WHEN f.price_usd < 200  THEN 'Entry Luxury'
        WHEN f.price_usd < 350  THEN 'Premium'
        ELSE 'Ultra Luxury'
    END AS price_tier,
    -- Snapshot timestamp
    CURRENT_TIMESTAMP AS snapshot_taken_at
FROM fragrances f
JOIN brands b ON f.brand_id = b.brand_id
LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
LEFT JOIN wishlists w ON f.fragrance_id = w.fragrance_id
LEFT JOIN fragrance_note_map fnm ON f.fragrance_id = fnm.fragrance_id
LEFT JOIN notes n ON fnm.note_id = n.note_id
GROUP BY
    f.fragrance_id, f.name, b.name, b.country,
    f.concentration, f.gender_target,
    f.price_usd, f.release_year;

-- Create an index on the materialized view for fast lookups
CREATE INDEX IF NOT EXISTS idx_mv_fragrance_snapshot_id
    ON mv_fragrance_daily_snapshot(fragrance_id);

CREATE INDEX IF NOT EXISTS idx_mv_fragrance_snapshot_score
    ON mv_fragrance_daily_snapshot(performance_score DESC);

CREATE INDEX IF NOT EXISTS idx_mv_fragrance_snapshot_tier
    ON mv_fragrance_daily_snapshot(price_tier);

-- =====================
-- MATERIALIZED VIEW 2: CUSTOMER SUMMARY SNAPSHOT
-- =====================
-- The customer profile view in reporting_views.sql joins
-- four tables and calculates twelve metrics per customer.
-- Fine for fifty customers. Sluggish for fifty thousand.
-- This materialized version pre-computes everything nightly
-- so the CRM dashboard loads in milliseconds.

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_customer_summary AS
WITH purchase_stats AS (
    SELECT
        user_id,
        COUNT(*) AS purchase_count,
        SUM(price_paid) AS total_spent,
        AVG(price_paid) AS avg_order_value,
        MIN(purchase_date) AS first_purchase,
        MAX(purchase_date) AS last_purchase,
        -- Personal purchase rhythm
        AVG(
            purchase_date - LAG(purchase_date) OVER (
                PARTITION BY user_id ORDER BY purchase_date ASC
            )
        ) AS avg_days_between_purchases
    FROM purchases
    GROUP BY user_id
),
rating_stats AS (
    SELECT
        user_id,
        COUNT(*) AS rating_count,
        AVG(score) AS avg_score
    FROM ratings
    GROUP BY user_id
),
wishlist_stats AS (
    SELECT
        user_id,
        COUNT(*) AS wishlist_count
    FROM wishlists
    GROUP BY user_id
)
SELECT
    u.user_id,
    u.username,
    u.email,
    u.age,
    u.country,
    u.joined_date,
    -- Purchase metrics
    COALESCE(ps.purchase_count, 0) AS total_purchases,
    ROUND(COALESCE(ps.total_spent, 0), 2) AS lifetime_value,
    ROUND(COALESCE(ps.avg_order_value, 0), 2) AS avg_order_value,
    ps.first_purchase AS first_purchase_date,
    ps.last_purchase AS last_purchase_date,
    EXTRACT(DAY FROM (
        CURRENT_DATE - ps.last_purchase
    ))::INT AS days_since_last_purchase,
    ROUND(COALESCE(ps.avg_days_between_purchases, 0), 0)
        AS personal_purchase_rhythm_days,
    -- Engagement metrics
    COALESCE(rs.rating_count, 0) AS total_reviews,
    ROUND(COALESCE(rs.avg_score, 0), 2) AS avg_rating_given,
    COALESCE(ws.wishlist_count, 0) AS wishlist_items,
    -- Churn risk relative to personal rhythm
    ROUND(
        EXTRACT(DAY FROM (CURRENT_DATE - ps.last_purchase)) /
        NULLIF(ps.avg_days_between_purchases, 0),
        2
    ) AS churn_risk_multiplier,
    -- Segments
    CASE
        WHEN COALESCE(ps.total_spent, 0) >= 500 THEN 'Platinum'
        WHEN COALESCE(ps.total_spent, 0) >= 250 THEN 'Gold'
        WHEN COALESCE(ps.total_spent, 0) >= 100 THEN 'Silver'
        WHEN COALESCE(ps.purchase_count, 0) > 0  THEN 'Bronze'
        ELSE 'Registered Only'
    END AS value_segment,
    CASE
        WHEN EXTRACT(DAY FROM (CURRENT_DATE - ps.last_purchase)) <= 30
            THEN 'Active'
        WHEN EXTRACT(DAY FROM (CURRENT_DATE - ps.last_purchase)) <= 90
            THEN 'At Risk'
        WHEN ps.last_purchase IS NULL
            THEN 'Never Purchased'
        ELSE 'Churned'
    END AS activity_status,
    -- Health index (simplified version for fast lookup)
    LEAST(
        COALESCE(ps.purchase_count, 0) * 12 +
        COALESCE(rs.rating_count, 0) * 8 +
        COALESCE(ws.wishlist_count, 0) * 5 +
        LEAST(COALESCE(ps.total_spent, 0) / 20, 25)::INT,
        100
    ) AS health_index,
    CURRENT_TIMESTAMP AS snapshot_taken_at
FROM users u
LEFT JOIN purchase_stats ps ON u.user_id = ps.user_id
LEFT JOIN rating_stats rs ON u.user_id = rs.user_id
LEFT JOIN wishlist_stats ws ON u.user_id = ws.user_id;

CREATE INDEX IF NOT EXISTS idx_mv_customer_summary_id
    ON mv_customer_summary(user_id);

CREATE INDEX IF NOT EXISTS idx_mv_customer_summary_segment
    ON mv_customer_summary(value_segment);

CREATE INDEX IF NOT EXISTS idx_mv_customer_summary_status
    ON mv_customer_summary(activity_status);

CREATE INDEX IF NOT EXISTS idx_mv_customer_summary_country
    ON mv_customer_summary(country);

-- =====================
-- MATERIALIZED VIEW 3: BRAND PERFORMANCE SNAPSHOT
-- =====================
-- Brand-level aggregates are queried constantly by the
-- commercial team — brand managers want to know how their
-- catalog is performing without waiting for a long query
-- to run every time they open the dashboard.

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_brand_performance AS
SELECT
    b.brand_id,
    b.name AS brand,
    b.country AS origin,
    b.founded_year,
    COUNT(DISTINCT f.fragrance_id) AS catalog_size,
    COUNT(DISTINCT p.purchase_id) AS total_purchases,
    COUNT(DISTINCT p.user_id) AS unique_buyers,
    ROUND(COALESCE(SUM(p.price_paid), 0), 2) AS total_revenue,
    ROUND(COALESCE(AVG(f.price_usd), 0), 2) AS avg_fragrance_price,
    ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_rating,
    COUNT(DISTINCT r.rating_id) AS total_reviews,
    COUNT(DISTINCT w.wishlist_id) AS total_wishlists,
    ROUND(
        COALESCE(SUM(p.price_paid), 0) /
        NULLIF(COUNT(DISTINCT f.fragrance_id), 0),
        2
    ) AS revenue_per_fragrance,
    CASE
        WHEN AVG(f.price_usd) >= 400 THEN 'Ultra Luxury'
        WHEN AVG(f.price_usd) >= 250 THEN 'Luxury'
        WHEN AVG(f.price_usd) >= 100 THEN 'Designer'
        ELSE 'Accessible'
    END AS brand_tier,
    CURRENT_TIMESTAMP AS snapshot_taken_at
FROM brands b
LEFT JOIN fragrances f ON b.brand_id = f.brand_id
LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
LEFT JOIN wishlists w ON f.fragrance_id = w.fragrance_id
GROUP BY b.brand_id, b.name, b.country, b.founded_year;

CREATE INDEX IF NOT EXISTS idx_mv_brand_performance_id
    ON mv_brand_performance(brand_id);

CREATE INDEX IF NOT EXISTS idx_mv_brand_performance_tier
    ON mv_brand_performance(brand_tier);

-- =====================
-- REFRESH STRATEGY
-- =====================
-- How often should each materialized view be refreshed?
-- The answer depends on how fresh the data needs to be
-- and how expensive the refresh is.

-- CONCURRENT refresh lets users query the old version
-- while the new one builds in the background.
-- This is critical for production — you do not want the
-- dashboard to go blank every time the view refreshes.

-- Refresh all three views (run this on a nightly schedule)
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_fragrance_daily_snapshot;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_customer_summary;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_brand_performance;

-- For CONCURRENT refresh to work the view needs a unique index.
-- Add these after the first non-concurrent refresh:
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_fragrance_unique
    ON mv_fragrance_daily_snapshot(fragrance_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_customer_unique
    ON mv_customer_summary(user_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_brand_unique
    ON mv_brand_performance(brand_id);

-- =====================
-- STALENESS MONITORING
-- =====================
-- How do you know if a materialized view is out of date?
-- This query checks the snapshot timestamp against the
-- most recent underlying data and flags anything stale.
-- Run this as a health check before every dashboard session.

SELECT
    'mv_fragrance_daily_snapshot' AS view_name,
    MAX(snapshot_taken_at) AS last_refreshed,
    EXTRACT(HOUR FROM (
        CURRENT_TIMESTAMP - MAX(snapshot_taken_at)
    ))::INT AS hours_since_refresh,
    CASE
        WHEN EXTRACT(HOUR FROM (
            CURRENT_TIMESTAMP - MAX(snapshot_taken_at)
        )) <= 24 THEN 'Fresh — refreshed within 24 hours'
        WHEN EXTRACT(HOUR FROM (
            CURRENT_TIMESTAMP - MAX(snapshot_taken_at)
        )) <= 48 THEN 'Acceptable — consider refreshing'
        ELSE 'Stale — refresh immediately'
    END AS freshness_status
FROM mv_fragrance_daily_snapshot

UNION ALL

SELECT
    'mv_customer_summary',
    MAX(snapshot_taken_at),
    EXTRACT(HOUR FROM (
        CURRENT_TIMESTAMP - MAX(snapshot_taken_at)
    ))::INT,
    CASE
        WHEN EXTRACT(HOUR FROM (
            CURRENT_TIMESTAMP - MAX(snapshot_taken_at)
        )) <= 24 THEN 'Fresh'
        WHEN EXTRACT(HOUR FROM (
            CURRENT_TIMESTAMP - MAX(snapshot_taken_at)
        )) <= 48 THEN 'Acceptable'
        ELSE 'Stale — refresh immediately'
    END
FROM mv_customer_summary

UNION ALL

SELECT
    'mv_brand_performance',
    MAX(snapshot_taken_at),
    EXTRACT(HOUR FROM (
        CURRENT_TIMESTAMP - MAX(snapshot_taken_at)
    ))::INT,
    CASE
        WHEN EXTRACT(HOUR FROM (
            CURRENT_TIMESTAMP - MAX(snapshot_taken_at)
        )) <= 24 THEN 'Fresh'
        WHEN EXTRACT(HOUR FROM (
            CURRENT_TIMESTAMP - MAX(snapshot_taken_at)
        )) <= 48 THEN 'Acceptable'
        ELSE 'Stale — refresh immediately'
    END
FROM mv_brand_performance;

-- =====================
-- QUERY PERFORMANCE COMPARISON
-- =====================
-- Use EXPLAIN ANALYZE to see the difference between
-- querying the raw tables vs the materialized view.
-- The numbers tell the story better than any explanation.

-- Against raw tables (slow at scale):
EXPLAIN ANALYZE
SELECT
    f.name,
    COUNT(p.purchase_id) AS purchases,
    AVG(r.score) AS avg_rating
FROM fragrances f
LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
GROUP BY f.name;

-- Against materialized view (fast at any scale):
EXPLAIN ANALYZE
SELECT fragrance, total_purchases, avg_rating
FROM mv_fragrance_daily_snapshot;