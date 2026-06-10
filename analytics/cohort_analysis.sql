-- ScentDB: Cohort Analysis
-- =====================
-- Cohort analysis is how you find out whether your platform
-- is actually retaining customers or just constantly replacing
-- churned ones with new ones. A business that looks healthy
-- on total revenue can be quietly dying if retention is poor —
-- you're just running faster to stay in the same place.
--
-- The idea is simple. Group users by the month they first
-- purchased. Then track what percentage of each group came
-- back and bought again in subsequent months. If month-one
-- cohorts show 60% retention at month three, you have a
-- genuinely sticky product. If they show 5%, you have a
-- problem no amount of new user acquisition will fix.
--
-- This is the analysis that separates analysts who can pull
-- numbers from ones who can tell you what the numbers mean.
-- Every growth team at every serious company runs some version
-- of this. Knowing how to build it from scratch — not just
-- read a dashboard someone else made — is what gets you in
-- the room where decisions actually happen.
-- =====================

-- =====================
-- STEP 1: ASSIGN USERS TO COHORTS
-- =====================
-- A cohort is just the month a user made their very first
-- purchase. Every subsequent purchase they make gets compared
-- back to that starting point. Simple in concept, genuinely
-- useful in practice.

WITH first_purchases AS (
    SELECT
        user_id,
        MIN(purchase_date) AS first_purchase_date,
        DATE_TRUNC('month', MIN(purchase_date)) AS cohort_month
    FROM purchases
    GROUP BY user_id
),
all_purchases AS (
    SELECT
        p.user_id,
        p.purchase_date,
        DATE_TRUNC('month', p.purchase_date) AS purchase_month,
        fp.cohort_month,
        -- How many months after their first purchase is this one?
        -- Month 0 = the cohort month itself (acquisition month)
        -- Month 1 = one month later, and so on
        EXTRACT(YEAR FROM AGE(
            DATE_TRUNC('month', p.purchase_date),
            fp.cohort_month
        )) * 12 +
        EXTRACT(MONTH FROM AGE(
            DATE_TRUNC('month', p.purchase_date),
            fp.cohort_month
        )) AS months_since_first_purchase
    FROM purchases p
    JOIN first_purchases fp ON p.user_id = fp.user_id
)
SELECT
    cohort_month,
    months_since_first_purchase,
    COUNT(DISTINCT user_id) AS active_users,
    COUNT(*) AS total_purchases,
    ROUND(AVG(
        -- We need monetary data joined in for the next step
        -- This is the structural query
        0
    ), 2) AS placeholder
FROM all_purchases
GROUP BY cohort_month, months_since_first_purchase
ORDER BY cohort_month, months_since_first_purchase;

-- =====================
-- STEP 2: COHORT RETENTION TABLE
-- =====================
-- This produces the classic retention grid you see in
-- every growth analytics presentation. Rows are cohorts
-- (month of first purchase). Columns are months 0 through N.
-- Each cell shows what percentage of the original cohort
-- was still active that many months later.
--
-- Reading it is straightforward. If row Jan-2024 shows
-- 100% at month 0 (everyone bought in their first month,
-- by definition), 60% at month 1, and 40% at month 2,
-- that means 40% of January's new customers were still
-- buying two months later. Whether that's good or bad
-- depends entirely on your industry and product type.

WITH first_purchases AS (
    SELECT
        user_id,
        DATE_TRUNC('month', MIN(purchase_date)) AS cohort_month
    FROM purchases
    GROUP BY user_id
),
cohort_size AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT user_id) AS cohort_total
    FROM first_purchases
    GROUP BY cohort_month
),
monthly_activity AS (
    SELECT
        fp.cohort_month,
        DATE_TRUNC('month', p.purchase_date) AS activity_month,
        COUNT(DISTINCT p.user_id) AS active_users
    FROM purchases p
    JOIN first_purchases fp ON p.user_id = fp.user_id
    GROUP BY fp.cohort_month, DATE_TRUNC('month', p.purchase_date)
),
retention_data AS (
    SELECT
        ma.cohort_month,
        cs.cohort_total,
        ma.activity_month,
        ma.active_users,
        EXTRACT(YEAR FROM AGE(ma.activity_month, ma.cohort_month)) * 12 +
        EXTRACT(MONTH FROM AGE(ma.activity_month, ma.cohort_month))
            AS month_number,
        ROUND(
            ma.active_users::DECIMAL / cs.cohort_total * 100,
            1
        ) AS retention_rate
    FROM monthly_activity ma
    JOIN cohort_size cs ON ma.cohort_month = cs.cohort_month
)
SELECT
    TO_CHAR(cohort_month, 'Mon YYYY') AS cohort,
    cohort_total AS cohort_size,
    MAX(CASE WHEN month_number = 0 THEN retention_rate END) AS "Month 0",
    MAX(CASE WHEN month_number = 1 THEN retention_rate END) AS "Month 1",
    MAX(CASE WHEN month_number = 2 THEN retention_rate END) AS "Month 2",
    MAX(CASE WHEN month_number = 3 THEN retention_rate END) AS "Month 3",
    MAX(CASE WHEN month_number = 4 THEN retention_rate END) AS "Month 4",
    MAX(CASE WHEN month_number = 5 THEN retention_rate END) AS "Month 5"
FROM retention_data
GROUP BY cohort_month, cohort_total
ORDER BY cohort_month;

-- =====================
-- STEP 3: REVENUE BY COHORT
-- =====================
-- Retention rate tells you if people came back.
-- Revenue by cohort tells you if it was worth it when they did.
-- A cohort with 40% retention but high average order value
-- is often more valuable than one with 70% retention
-- buying small amounts each time.
--
-- This is the nuance most junior analysts miss. They optimise
-- for retention rate and wonder why revenue is flat. The two
-- numbers need to be read together.

WITH first_purchases AS (
    SELECT
        user_id,
        DATE_TRUNC('month', MIN(purchase_date)) AS cohort_month
    FROM purchases
    GROUP BY user_id
),
cohort_revenue AS (
    SELECT
        fp.cohort_month,
        DATE_TRUNC('month', p.purchase_date) AS purchase_month,
        COUNT(DISTINCT p.user_id) AS active_users,
        SUM(p.price_paid) AS monthly_revenue,
        ROUND(AVG(p.price_paid), 2) AS avg_order_value,
        COUNT(p.purchase_id) AS total_orders,
        EXTRACT(YEAR FROM AGE(
            DATE_TRUNC('month', p.purchase_date),
            fp.cohort_month
        )) * 12 +
        EXTRACT(MONTH FROM AGE(
            DATE_TRUNC('month', p.purchase_date),
            fp.cohort_month
        )) AS month_number
    FROM purchases p
    JOIN first_purchases fp ON p.user_id = fp.user_id
    GROUP BY fp.cohort_month,
             DATE_TRUNC('month', p.purchase_date)
)
SELECT
    TO_CHAR(cohort_month, 'Mon YYYY') AS cohort,
    month_number AS months_since_acquisition,
    active_users,
    ROUND(monthly_revenue, 2) AS revenue,
    avg_order_value,
    total_orders,
    -- Revenue per user in this cohort this month
    ROUND(monthly_revenue / NULLIF(active_users, 0), 2) AS revenue_per_active_user
FROM cohort_revenue
ORDER BY cohort_month, month_number;

-- =====================
-- STEP 4: COHORT BEHAVIOUR PATTERNS
-- =====================
-- Beyond the numbers, what are different cohorts actually
-- buying? Do early adopters (first cohorts) gravitate toward
-- different fragrance families than more recent ones?
-- Does average spend go up or down over cohort generations?
-- These questions matter for product strategy — if your
-- newest cohorts are spending less, something changed.
-- Either your acquisition is bringing in lower-value users,
-- your product got worse, or the market shifted.
-- You cannot know which without this analysis.

WITH first_purchases AS (
    SELECT
        user_id,
        DATE_TRUNC('month', MIN(purchase_date)) AS cohort_month
    FROM purchases
    GROUP BY user_id
)
SELECT
    TO_CHAR(fp.cohort_month, 'Mon YYYY') AS cohort,
    f.gender_target AS fragrance_category,
    f.concentration,
    COUNT(DISTINCT p.user_id) AS unique_buyers,
    COUNT(p.purchase_id) AS total_purchases,
    ROUND(AVG(p.price_paid), 2) AS avg_spend,
    ROUND(SUM(p.price_paid), 2) AS cohort_category_revenue
FROM purchases p
JOIN first_purchases fp ON p.user_id = fp.user_id
JOIN fragrances f ON p.fragrance_id = f.fragrance_id
GROUP BY fp.cohort_month, f.gender_target, f.concentration
ORDER BY fp.cohort_month, cohort_category_revenue DESC;

-- =====================
-- STEP 5: EARLY SIGNALS OF CHURN
-- =====================
-- The most valuable thing cohort analysis can do is tell you
-- who is about to leave before they actually do. By the time
-- someone has churned they are already gone. The signal to
-- act on is the drop — users whose purchase frequency is
-- slowing down within their cohort's normal pattern.
--
-- This query finds users who were active in their first month
-- but have not purchased since. These are not lost causes yet.
-- They bought once, which means something interested them.
-- Something also stopped them from coming back. That gap
-- is the most actionable problem on the platform.

WITH first_purchases AS (
    SELECT
        user_id,
        MIN(purchase_date) AS first_purchase_date,
        DATE_TRUNC('month', MIN(purchase_date)) AS cohort_month
    FROM purchases
    GROUP BY user_id
),
purchase_counts AS (
    SELECT
        user_id,
        COUNT(*) AS total_purchases,
        MAX(purchase_date) AS last_purchase_date
    FROM purchases
    GROUP BY user_id
)
SELECT
    u.username,
    u.email,
    u.country,
    TO_CHAR(fp.cohort_month, 'Mon YYYY') AS acquisition_cohort,
    fp.first_purchase_date,
    pc.last_purchase_date,
    pc.total_purchases,
    EXTRACT(DAY FROM (
        CURRENT_DATE - pc.last_purchase_date
    ))::INT AS days_since_last_purchase,
    CASE
        WHEN pc.total_purchases = 1
            THEN 'One-time buyer — never returned'
        WHEN EXTRACT(DAY FROM (CURRENT_DATE - pc.last_purchase_date)) > 90
            THEN 'Lapsing — no purchase in 90+ days'
        WHEN EXTRACT(DAY FROM (CURRENT_DATE - pc.last_purchase_date)) > 60
            THEN 'At risk — no purchase in 60+ days'
        ELSE 'Active'
    END AS churn_risk,
    CASE
        WHEN pc.total_purchases = 1
            THEN 'Send second-purchase incentive — 15% off next order'
        WHEN EXTRACT(DAY FROM (CURRENT_DATE - pc.last_purchase_date)) > 90
            THEN 'Win-back campaign — highlight new arrivals since last visit'
        WHEN EXTRACT(DAY FROM (CURRENT_DATE - pc.last_purchase_date)) > 60
            THEN 'Re-engagement email — personalised recommendations'
        ELSE 'No action needed — continue standard communication'
    END AS recommended_action
FROM users u
JOIN first_purchases fp ON u.user_id = fp.user_id
JOIN purchase_counts pc ON u.user_id = pc.user_id
ORDER BY days_since_last_purchase DESC;

-- =====================
-- STEP 6: COHORT LIFETIME VALUE PROJECTION
-- =====================
-- Pull everything together into a single forward-looking view.
-- For each cohort, what is the total revenue generated so far,
-- what is the average per-user value, and based on current
-- retention trends what might they generate over the next year?
--
-- This is the number a CFO actually cares about.
-- Everything else in this file builds toward this.

WITH first_purchases AS (
    SELECT
        user_id,
        DATE_TRUNC('month', MIN(purchase_date)) AS cohort_month
    FROM purchases
    GROUP BY user_id
),
cohort_metrics AS (
    SELECT
        fp.cohort_month,
        COUNT(DISTINCT fp.user_id) AS cohort_size,
        COUNT(p.purchase_id) AS total_orders,
        SUM(p.price_paid) AS total_revenue,
        ROUND(AVG(p.price_paid), 2) AS avg_order_value,
        COUNT(p.purchase_id)::DECIMAL /
            COUNT(DISTINCT fp.user_id) AS orders_per_user,
        MAX(p.purchase_date) - MIN(p.purchase_date) AS observation_window
    FROM first_purchases fp
    LEFT JOIN purchases p ON fp.user_id = p.user_id
    GROUP BY fp.cohort_month
)
SELECT
    TO_CHAR(cohort_month, 'Mon YYYY') AS cohort,
    cohort_size,
    total_orders,
    ROUND(total_revenue, 2) AS total_revenue_to_date,
    ROUND(total_revenue / NULLIF(cohort_size, 0), 2) AS revenue_per_user,
    avg_order_value,
    ROUND(orders_per_user, 2) AS avg_orders_per_user,
    -- Simple 12-month projection based on observed velocity
    ROUND(
        (total_revenue / NULLIF(
            GREATEST(EXTRACT(DAY FROM observation_window), 1), 0
        )) * 365,
        2
    ) AS projected_annual_revenue,
    ROUND(
        (total_revenue / NULLIF(cohort_size, 0) /
        NULLIF(GREATEST(EXTRACT(DAY FROM observation_window), 1), 0)) * 365,
        2
    ) AS projected_annual_value_per_user
FROM cohort_metrics
ORDER BY cohort_month;