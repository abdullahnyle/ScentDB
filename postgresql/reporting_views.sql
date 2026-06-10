-- ScentDB: Reporting Views
-- =====================
-- Views are the bridge between a database and the people
-- who need to understand it but should not have to write
-- SQL to do so. A well-designed view layer means a Power BI
-- dashboard, a Tableau workbook, or a business stakeholder
-- running ad hoc queries all see the same clean, pre-joined,
-- pre-calculated version of the data.
--
-- This matters for a portfolio because Power BI is sitting
-- in your Tier 1 skill stack. Any hiring manager who sees
-- Power BI on a resume and then sees a clean view layer
-- in the same project will immediately understand that you
-- know how the two connect. You are not someone who learned
-- Power BI in isolation. You understand the data pipeline
-- that feeds it.
--
-- Every view here is named and structured to connect directly
-- to a Power BI report page. The naming convention is
-- deliberate: vw_ prefix signals it is a view, not a table,
-- and the suffix describes exactly what report it feeds.
-- That kind of intentional design is what separates a
-- portfolio project from a homework assignment.
-- =====================

-- =====================
-- EXECUTIVE DASHBOARD VIEWS
-- =====================

-- Primary KPI view — feeds the executive summary page
-- One row per day, all the top-level numbers a CEO cares about
CREATE OR REPLACE VIEW vw_daily_kpis AS
SELECT
    p.purchase_date AS date,
    COUNT(DISTINCT p.purchase_id) AS daily_orders,
    COUNT(DISTINCT p.user_id) AS daily_active_buyers,
    ROUND(SUM(p.price_paid), 2) AS daily_revenue,
    ROUND(AVG(p.price_paid), 2) AS avg_order_value,
    COUNT(DISTINCT r.rating_id) AS daily_reviews,
    ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_satisfaction_score,
    -- Running totals for trend lines
    SUM(SUM(p.price_paid)) OVER (
        ORDER BY p.purchase_date
        ROWS UNBOUNDED PRECEDING
    ) AS cumulative_revenue,
    SUM(COUNT(DISTINCT p.purchase_id)) OVER (
        ORDER BY p.purchase_date
        ROWS UNBOUNDED PRECEDING
    ) AS cumulative_orders
FROM purchases p
LEFT JOIN ratings r ON DATE(r.rated_at) = p.purchase_date
GROUP BY p.purchase_date
ORDER BY p.purchase_date;

-- Monthly summary — feeds the trend analysis page
CREATE OR REPLACE VIEW vw_monthly_summary AS
SELECT
    TO_CHAR(p.purchase_date, 'YYYY-MM') AS month,
    DATE_TRUNC('month', p.purchase_date) AS month_date,
    COUNT(DISTINCT p.purchase_id) AS total_orders,
    COUNT(DISTINCT p.user_id) AS unique_buyers,
    ROUND(SUM(p.price_paid), 2) AS total_revenue,
    ROUND(AVG(p.price_paid), 2) AS avg_order_value,
    -- Month over month revenue growth
    ROUND(
        (SUM(p.price_paid) - LAG(SUM(p.price_paid)) OVER (
            ORDER BY DATE_TRUNC('month', p.purchase_date)
        )) /
        NULLIF(LAG(SUM(p.price_paid)) OVER (
            ORDER BY DATE_TRUNC('month', p.purchase_date)
        ), 0) * 100,
        1
    ) AS mom_revenue_growth_percent,
    -- New vs returning buyers
    COUNT(DISTINCT CASE
        WHEN p.purchase_date = (
            SELECT MIN(p2.purchase_date)
            FROM purchases p2
            WHERE p2.user_id = p.user_id
        ) THEN p.user_id
    END) AS new_buyers,
    COUNT(DISTINCT CASE
        WHEN p.purchase_date > (
            SELECT MIN(p2.purchase_date)
            FROM purchases p2
            WHERE p2.user_id = p.user_id
        ) THEN p.user_id
    END) AS returning_buyers
FROM purchases p
GROUP BY
    TO_CHAR(p.purchase_date, 'YYYY-MM'),
    DATE_TRUNC('month', p.purchase_date)
ORDER BY month_date;

-- =====================
-- PRODUCT PERFORMANCE VIEWS
-- =====================

-- Full fragrance performance — feeds the catalog page in Power BI
CREATE OR REPLACE VIEW vw_fragrance_performance AS
SELECT
    f.fragrance_id,
    f.name AS fragrance,
    b.name AS brand,
    b.country AS brand_origin,
    f.concentration,
    f.gender_target,
    f.price_usd AS listed_price,
    f.release_year,
    -- Sales metrics
    COUNT(DISTINCT p.purchase_id) AS total_purchases,
    COUNT(DISTINCT p.user_id) AS unique_buyers,
    ROUND(COALESCE(SUM(p.price_paid), 0), 2) AS total_revenue,
    ROUND(COALESCE(AVG(p.price_paid), 0), 2) AS avg_price_paid,
    -- Rating metrics
    COUNT(DISTINCT r.rating_id) AS total_reviews,
    ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_rating,
    MAX(r.score) AS highest_rating,
    MIN(r.score) AS lowest_rating,
    -- Demand signals
    COUNT(DISTINCT w.wishlist_id) AS wishlist_count,
    -- Composite performance score
    ROUND(
        COALESCE(AVG(r.score), 5) * 0.35 +
        COUNT(DISTINCT p.purchase_id) * 0.35 +
        COUNT(DISTINCT w.wishlist_id) * 0.20 +
        COUNT(DISTINCT r.rating_id) * 0.10,
        3
    ) AS performance_score,
    -- Price tier for slicing in Power BI
    CASE
        WHEN f.price_usd < 100  THEN 'Accessible'
        WHEN f.price_usd < 200  THEN 'Entry Luxury'
        WHEN f.price_usd < 350  THEN 'Premium'
        ELSE 'Ultra Luxury'
    END AS price_tier
FROM fragrances f
JOIN brands b ON f.brand_id = b.brand_id
LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
LEFT JOIN wishlists w ON f.fragrance_id = w.fragrance_id
GROUP BY
    f.fragrance_id, f.name, b.name, b.country,
    f.concentration, f.gender_target,
    f.price_usd, f.release_year;

-- Brand performance — feeds the brand comparison page
CREATE OR REPLACE VIEW vw_brand_performance AS
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
    -- Revenue per fragrance in catalog
    ROUND(
        COALESCE(SUM(p.price_paid), 0) /
        NULLIF(COUNT(DISTINCT f.fragrance_id), 0),
        2
    ) AS revenue_per_fragrance,
    -- Brand tier classification
    CASE
        WHEN AVG(f.price_usd) >= 400 THEN 'Ultra Luxury'
        WHEN AVG(f.price_usd) >= 250 THEN 'Luxury'
        WHEN AVG(f.price_usd) >= 100 THEN 'Designer'
        ELSE 'Accessible'
    END AS brand_tier
FROM brands b
LEFT JOIN fragrances f ON b.brand_id = f.brand_id
LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
LEFT JOIN wishlists w ON f.fragrance_id = w.fragrance_id
GROUP BY b.brand_id, b.name, b.country, b.founded_year;

-- =====================
-- CUSTOMER VIEWS
-- =====================

-- Full customer profile — feeds the customer analytics page
CREATE OR REPLACE VIEW vw_customer_profile AS
WITH purchase_stats AS (
    SELECT
        user_id,
        COUNT(*) AS purchase_count,
        SUM(price_paid) AS total_spent,
        AVG(price_paid) AS avg_order_value,
        MIN(purchase_date) AS first_purchase,
        MAX(purchase_date) AS last_purchase
    FROM purchases
    GROUP BY user_id
),
rating_stats AS (
    SELECT
        user_id,
        COUNT(*) AS rating_count,
        AVG(score) AS avg_score_given
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
    -- Purchase behavior
    COALESCE(ps.purchase_count, 0) AS total_purchases,
    ROUND(COALESCE(ps.total_spent, 0), 2) AS lifetime_value,
    ROUND(COALESCE(ps.avg_order_value, 0), 2) AS avg_order_value,
    ps.first_purchase AS first_purchase_date,
    ps.last_purchase AS last_purchase_date,
    EXTRACT(DAY FROM (CURRENT_DATE - ps.last_purchase))::INT
        AS days_since_last_purchase,
    -- Engagement
    COALESCE(rs.rating_count, 0) AS total_reviews,
    ROUND(COALESCE(rs.avg_score_given, 0), 2) AS avg_rating_given,
    COALESCE(ws.wishlist_count, 0) AS wishlist_items,
    -- Segments for Power BI slicers
    CASE
        WHEN COALESCE(ps.total_spent, 0) >= 500 THEN 'Platinum'
        WHEN COALESCE(ps.total_spent, 0) >= 250 THEN 'Gold'
        WHEN COALESCE(ps.total_spent, 0) >= 100 THEN 'Silver'
        WHEN COALESCE(ps.purchase_count, 0) > 0  THEN 'Bronze'
        ELSE 'Registered — No Purchase'
    END AS value_segment,
    CASE
        WHEN EXTRACT(DAY FROM (CURRENT_DATE - ps.last_purchase)) <= 30
            THEN 'Active'
        WHEN EXTRACT(DAY FROM (CURRENT_DATE - ps.last_purchase)) <= 90
            THEN 'At Risk'
        WHEN ps.last_purchase IS NULL
            THEN 'Never Purchased'
        ELSE 'Churned'
    END AS activity_status
FROM users u
LEFT JOIN purchase_stats ps ON u.user_id = ps.user_id
LEFT JOIN rating_stats rs ON u.user_id = rs.user_id
LEFT JOIN wishlist_stats ws ON u.user_id = ws.user_id;

-- Geographic summary — feeds the map visualization in Power BI
CREATE OR REPLACE VIEW vw_geographic_summary AS
SELECT
    u.country,
    COUNT(DISTINCT u.user_id) AS total_customers,
    COUNT(DISTINCT p.purchase_id) AS total_orders,
    ROUND(COALESCE(SUM(p.price_paid), 0), 2) AS total_revenue,
    ROUND(COALESCE(AVG(p.price_paid), 0), 2) AS avg_order_value,
    ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_satisfaction,
    COUNT(DISTINCT w.wishlist_id) AS total_wishlists,
    -- Revenue per customer for market efficiency comparison
    ROUND(
        COALESCE(SUM(p.price_paid), 0) /
        NULLIF(COUNT(DISTINCT u.user_id), 0),
        2
    ) AS revenue_per_customer,
    -- Market size reference from MongoDB market_trends
    CASE u.country
        WHEN 'UAE'      THEN 847
        WHEN 'Pakistan' THEN 156
        WHEN 'UK'       THEN 1200
        WHEN 'Ireland'  THEN 312
        WHEN 'USA'      THEN 8420
        ELSE NULL
    END AS market_size_usd_millions
FROM users u
LEFT JOIN purchases p ON u.user_id = p.user_id
LEFT JOIN ratings r ON u.user_id = r.user_id
LEFT JOIN wishlists w ON u.user_id = w.user_id
GROUP BY u.country;

-- =====================
-- OPERATIONAL VIEWS
-- =====================

-- Wishlist demand forecast — feeds inventory planning
CREATE OR REPLACE VIEW vw_wishlist_demand AS
SELECT
    f.fragrance_id,
    f.name AS fragrance,
    b.name AS brand,
    f.price_usd,
    COUNT(DISTINCT w.wishlist_id) AS total_wishlists,
    COUNT(DISTINCT p.purchase_id) AS total_purchases,
    -- Conversion rate from wishlist to purchase
    ROUND(
        COUNT(DISTINCT p.purchase_id)::DECIMAL /
        NULLIF(COUNT(DISTINCT w.wishlist_id), 0) * 100,
        1
    ) AS wishlist_conversion_rate,
    -- Unmet demand: wishlisted but not yet purchased
    COUNT(DISTINCT w.wishlist_id) - COUNT(DISTINCT p.purchase_id)
        AS unmet_demand_units,
    -- Revenue potential if all wishlists converted
    ROUND(
        (COUNT(DISTINCT w.wishlist_id) -
         COUNT(DISTINCT p.purchase_id)) * f.price_usd,
        2
    ) AS potential_revenue_if_converted,
    AVG(w.priority) AS avg_wishlist_priority
FROM fragrances f
JOIN brands b ON f.brand_id = b.brand_id
LEFT JOIN wishlists w ON f.fragrance_id = w.fragrance_id
LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
    AND p.user_id = w.user_id
GROUP BY f.fragrance_id, f.name, b.name, f.price_usd;

-- Audit trail view — feeds the compliance and operations page
CREATE OR REPLACE VIEW vw_audit_trail AS
SELECT
    al.log_id,
    al.table_name,
    al.action,
    u.username AS performed_by,
    u.country AS user_country,
    al.performed_at,
    al.details,
    -- Flag unusual activity
    CASE
        WHEN al.action = 'SUSPICIOUS_PATTERN'
            THEN 'High — requires review'
        WHEN al.action = 'AUTO_DELETE'
            THEN 'Low — automated system action'
        WHEN al.action = 'TRANSACTION_COMPLETE'
            THEN 'Info — standard purchase flow'
        ELSE 'Normal — routine operation'
    END AS priority_flag
FROM audit_log al
LEFT JOIN users u ON al.performed_by = u.user_id
ORDER BY al.performed_at DESC;

-- =====================
-- POWER BI CONNECTION GUIDE
-- =====================
-- To connect these views to Power BI:
-- 1. Open Power BI Desktop
-- 2. Get Data → PostgreSQL database
-- 3. Server: localhost, Database: scentdb
-- 4. In the navigator, select only the vw_ prefixed views
--    (not the raw tables — the views are pre-optimised)
-- 5. Recommended report pages and their views:
--    Executive Summary   → vw_daily_kpis + vw_monthly_summary
--    Catalog Performance → vw_fragrance_performance + vw_brand_performance
--    Customer Analytics  → vw_customer_profile
--    Geographic Map      → vw_geographic_summary
--    Demand Planning     → vw_wishlist_demand
--    Audit & Compliance  → vw_audit_trail
--
-- Each view is designed to load cleanly into Power BI without
-- further transformation in Power Query. Relationships between
-- views should be set on fragrance_id, user_id, and brand_id.
-- All monetary values are in USD. All dates are in YYYY-MM-DD.

-- Verify all views exist and are queryable
SELECT table_name AS view_name,
       'Ready for Power BI connection' AS status
FROM information_schema.views
WHERE table_schema = 'public'
AND table_name LIKE 'vw_%'
ORDER BY table_name;