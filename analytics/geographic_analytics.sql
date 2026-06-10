-- ScentDB: Geographic Analytics
-- =====================
-- Geography matters more in fragrance than almost any other
-- consumer category. A scent that dominates in Lahore in July
-- would be a strange choice for Dublin in January. Climate,
-- culture, income levels, and local taste traditions all shape
-- what people buy and how much they spend doing it.
--
-- This file builds the geographic layer of ScentDB's analytics.
-- It ties the structured transactional data in PostgreSQL directly
-- to the regional market trend data sitting in MongoDB — two
-- databases solving two different parts of the same question.
-- PostgreSQL tells you what your actual customers did.
-- MongoDB tells you what the broader market is doing.
-- Reading them together is where the real insight lives.
--
-- For a business analytics portfolio this file demonstrates
-- something specific and valuable: the ability to think about
-- data across systems, not just within a single table.
-- That cross-system thinking is exactly what separates a
-- junior analyst from someone ready to work on real problems.
-- =====================

-- =====================
-- COUNTRY LEVEL PERFORMANCE OVERVIEW
-- =====================
-- The simplest starting point: how does each country perform
-- on the metrics that actually matter to the business?
-- Revenue, order frequency, average spend, and engagement.
-- This is the table a regional manager asks for every quarter.

SELECT
    u.country,
    COUNT(DISTINCT u.user_id) AS total_customers,
    COUNT(DISTINCT p.purchase_id) AS total_orders,
    ROUND(SUM(p.price_paid), 2) AS total_revenue,
    ROUND(AVG(p.price_paid), 2) AS avg_order_value,
    ROUND(SUM(p.price_paid) / NULLIF(COUNT(DISTINCT u.user_id), 0), 2)
        AS revenue_per_customer,
    ROUND(COUNT(DISTINCT p.purchase_id)::DECIMAL /
        NULLIF(COUNT(DISTINCT u.user_id), 0), 2)
        AS orders_per_customer,
    COUNT(DISTINCT r.rating_id) AS total_reviews,
    ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_rating,
    COUNT(DISTINCT w.wishlist_id) AS total_wishlists,
    -- Engagement ratio: reviews + wishlists per customer
    ROUND(
        (COUNT(DISTINCT r.rating_id) +
         COUNT(DISTINCT w.wishlist_id))::DECIMAL /
        NULLIF(COUNT(DISTINCT u.user_id), 0),
        2
    ) AS engagement_per_customer
FROM users u
LEFT JOIN purchases p ON u.user_id = p.user_id
LEFT JOIN ratings r ON u.user_id = r.user_id
LEFT JOIN wishlists w ON u.user_id = w.user_id
GROUP BY u.country
ORDER BY total_revenue DESC;

-- =====================
-- REGIONAL FRAGRANCE PREFERENCES
-- =====================
-- Do customers from different countries gravitate toward
-- different fragrance types? The data here is small but
-- the query pattern scales to millions of rows without
-- changing a single line. That scalability is worth noting
-- when you walk someone through it.

SELECT
    u.country,
    f.gender_target AS fragrance_category,
    f.concentration,
    COUNT(DISTINCT p.purchase_id) AS purchases,
    ROUND(SUM(p.price_paid), 2) AS revenue,
    ROUND(AVG(p.price_paid), 2) AS avg_spend,
    ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_rating,
    -- Share of that country's total purchases
    ROUND(
        COUNT(DISTINCT p.purchase_id)::DECIMAL /
        SUM(COUNT(DISTINCT p.purchase_id)) OVER (PARTITION BY u.country) * 100,
        1
    ) AS share_of_country_purchases
FROM users u
JOIN purchases p ON u.user_id = p.user_id
JOIN fragrances f ON p.fragrance_id = f.fragrance_id
LEFT JOIN ratings r ON u.user_id = r.user_id
    AND p.fragrance_id = r.fragrance_id
GROUP BY u.country, f.gender_target, f.concentration
ORDER BY u.country, purchases DESC;

-- =====================
-- PRICE SENSITIVITY BY COUNTRY
-- =====================
-- Some markets are price sensitive and some are not.
-- Knowing which is which matters for promotions,
-- for catalog curation, and for deciding where to
-- invest in customer acquisition.
-- A country with high average spend and high engagement
-- is worth acquiring customers in even at higher CAC.
-- A country with low spend and low engagement needs a
-- different approach entirely.

WITH country_spend AS (
    SELECT
        u.country,
        u.user_id,
        SUM(p.price_paid) AS user_total_spend,
        COUNT(p.purchase_id) AS user_purchase_count,
        AVG(p.price_paid) AS user_avg_spend
    FROM users u
    JOIN purchases p ON u.user_id = p.user_id
    GROUP BY u.country, u.user_id
)
SELECT
    country,
    COUNT(user_id) AS customers,
    ROUND(AVG(user_total_spend), 2) AS avg_customer_lifetime_spend,
    ROUND(AVG(user_avg_spend), 2) AS avg_order_value,
    ROUND(MIN(user_avg_spend), 2) AS lowest_avg_spend,
    ROUND(MAX(user_avg_spend), 2) AS highest_avg_spend,
    ROUND(STDDEV(user_avg_spend), 2) AS spend_variation,
    -- How consistent is spending within this country?
    -- Low variation = predictable market
    -- High variation = mixed segments needing different approaches
    CASE
        WHEN STDDEV(user_avg_spend) < 50
            THEN 'Consistent market — single tier approach works'
        WHEN STDDEV(user_avg_spend) < 150
            THEN 'Mixed market — two tier approach recommended'
        ELSE 'Highly varied — full segmentation needed'
    END AS market_approach,
    CASE
        WHEN AVG(user_avg_spend) >= 300
            THEN 'Premium market — lead with luxury catalog'
        WHEN AVG(user_avg_spend) >= 150
            THEN 'Mid market — balanced catalog performs best'
        ELSE 'Accessible market — entry and mid tier focus'
    END AS catalog_strategy
FROM country_spend
GROUP BY country
ORDER BY avg_customer_lifetime_spend DESC;

-- =====================
-- GEOGRAPHIC MARKET PENETRATION
-- =====================
-- Market penetration asks a different question from revenue.
-- Revenue tells you how much you made in a market.
-- Penetration tells you how much of the available market
-- you are actually reaching.
--
-- We proxy available market size using the MongoDB
-- market_trends data — this query sets up the PostgreSQL
-- side of that cross-database join. In a production system
-- this would pull directly from a data warehouse that
-- has already unified both sources. Here we document
-- the query pattern and note where the MongoDB data connects.

SELECT
    u.country,
    COUNT(DISTINCT u.user_id) AS platform_customers,
    COUNT(DISTINCT p.purchase_id) AS total_orders,
    ROUND(SUM(p.price_paid), 2) AS platform_revenue_usd,
    -- These figures would come from MongoDB market_trends
    -- in a unified warehouse. Values below are from that collection.
    CASE u.country
        WHEN 'UAE'      THEN 847
        WHEN 'Pakistan' THEN 156
        WHEN 'UK'       THEN 1200
        WHEN 'Ireland'  THEN 312
        WHEN 'USA'      THEN 8420
        ELSE NULL
    END AS total_market_size_usd_millions,
    -- Platform revenue as a fraction of total market
    -- Even at scale this would be a small number
    -- which is the point — the opportunity is enormous
    ROUND(
        SUM(p.price_paid) /
        NULLIF(
            CASE u.country
                WHEN 'UAE'      THEN 847000000
                WHEN 'Pakistan' THEN 156000000
                WHEN 'UK'       THEN 1200000000
                WHEN 'Ireland'  THEN 312000000
                WHEN 'USA'      THEN 8420000000
                ELSE NULL
            END,
            0
        ) * 100,
        6
    ) AS market_share_percent,
    -- YoY growth rates from MongoDB market_trends collection
    CASE u.country
        WHEN 'UAE'      THEN 12.4
        WHEN 'Pakistan' THEN 8.2
        WHEN 'UK'       THEN 5.8
        WHEN 'Ireland'  THEN 5.1
        WHEN 'USA'      THEN 6.8
        ELSE NULL
    END AS market_yoy_growth_percent,
    -- Is this a growing or contracting market?
    CASE
        WHEN CASE u.country
                 WHEN 'UAE'      THEN 12.4
                 WHEN 'Pakistan' THEN 8.2
                 WHEN 'UK'       THEN 5.8
                 WHEN 'Ireland'  THEN 5.1
                 WHEN 'USA'      THEN 6.8
                 ELSE 0
             END >= 10
            THEN 'High growth — prioritise acquisition investment'
        WHEN CASE u.country
                 WHEN 'UAE'      THEN 12.4
                 WHEN 'Pakistan' THEN 8.2
                 WHEN 'UK'       THEN 5.8
                 WHEN 'Ireland'  THEN 5.1
                 WHEN 'USA'      THEN 6.8
                 ELSE 0
             END >= 5
            THEN 'Steady growth — maintain and optimise'
        ELSE 'Slow growth — focus on retention over acquisition'
    END AS market_investment_strategy
FROM users u
LEFT JOIN purchases p ON u.user_id = p.user_id
GROUP BY u.country
ORDER BY platform_revenue_usd DESC;

-- =====================
-- SEASONAL PATTERNS BY REGION
-- =====================
-- Fragrance buying is seasonal and the seasons are different
-- everywhere. Pakistan's buying pattern peaks in winter when
-- heavy orientals and ouds make sense in cooler temperatures.
-- Ireland peaks in autumn and winter for the same reason.
-- Australia peaks in their summer with fresh and aquatic
-- categories doing the heavy lifting.
-- This query extracts whatever seasonal signal exists
-- in the current purchase data and flags where it aligns
-- with the market trend expectations from MongoDB.

SELECT
    u.country,
    TO_CHAR(p.purchase_date, 'Month') AS purchase_month,
    EXTRACT(MONTH FROM p.purchase_date) AS month_number,
    COUNT(p.purchase_id) AS orders,
    ROUND(SUM(p.price_paid), 2) AS revenue,
    ROUND(AVG(p.price_paid), 2) AS avg_order_value,
    -- Tag the season based on country and month
    -- Northern hemisphere countries follow standard seasons
    -- Australia is reversed
    CASE
        WHEN u.country = 'Australia'
            THEN CASE
                WHEN EXTRACT(MONTH FROM p.purchase_date) IN (12, 1, 2)
                    THEN 'Summer'
                WHEN EXTRACT(MONTH FROM p.purchase_date) IN (3, 4, 5)
                    THEN 'Autumn'
                WHEN EXTRACT(MONTH FROM p.purchase_date) IN (6, 7, 8)
                    THEN 'Winter'
                ELSE 'Spring'
            END
        ELSE
            CASE
                WHEN EXTRACT(MONTH FROM p.purchase_date) IN (12, 1, 2)
                    THEN 'Winter'
                WHEN EXTRACT(MONTH FROM p.purchase_date) IN (3, 4, 5)
                    THEN 'Spring'
                WHEN EXTRACT(MONTH FROM p.purchase_date) IN (6, 7, 8)
                    THEN 'Summer'
                ELSE 'Autumn'
            END
    END AS local_season,
    -- Fragrance families bought in this period
    STRING_AGG(DISTINCT f.gender_target, ', ') AS categories_purchased
FROM users u
JOIN purchases p ON u.user_id = p.user_id
JOIN fragrances f ON p.fragrance_id = f.fragrance_id
GROUP BY u.country, TO_CHAR(p.purchase_date, 'Month'),
         EXTRACT(MONTH FROM p.purchase_date)
ORDER BY u.country, month_number;

-- =====================
-- HIGH VALUE CUSTOMER IDENTIFICATION BY REGION
-- =====================
-- Every region has its own definition of a high value customer
-- because average spend differs so much across markets.
-- A customer spending $300 in Pakistan is behaving very
-- differently from a customer spending $300 in the UAE.
-- This query identifies high value customers relative to
-- their own regional average rather than a global benchmark.
-- That relative definition is more useful for regional
-- marketing teams than an absolute dollar threshold.

WITH regional_averages AS (
    SELECT
        u.country,
        AVG(p.price_paid) AS country_avg_spend,
        STDDEV(p.price_paid) AS country_spend_stddev
    FROM users u
    JOIN purchases p ON u.user_id = p.user_id
    GROUP BY u.country
),
user_spend AS (
    SELECT
        u.user_id,
        u.username,
        u.email,
        u.country,
        SUM(p.price_paid) AS total_spend,
        AVG(p.price_paid) AS avg_spend,
        COUNT(p.purchase_id) AS purchase_count
    FROM users u
    JOIN purchases p ON u.user_id = p.user_id
    GROUP BY u.user_id, u.username, u.email, u.country
)
SELECT
    us.username,
    us.email,
    us.country,
    ROUND(us.total_spend, 2) AS total_spend,
    ROUND(us.avg_spend, 2) AS avg_spend,
    us.purchase_count,
    ROUND(ra.country_avg_spend, 2) AS country_avg_spend,
    -- How many standard deviations above the country average?
    ROUND(
        (us.avg_spend - ra.country_avg_spend) /
        NULLIF(ra.country_spend_stddev, 0),
        2
    ) AS spend_z_score,
    CASE
        WHEN (us.avg_spend - ra.country_avg_spend) /
             NULLIF(ra.country_spend_stddev, 0) >= 1.5
            THEN 'Regional VIP — top spender in their market'
        WHEN (us.avg_spend - ra.country_avg_spend) /
             NULLIF(ra.country_spend_stddev, 0) >= 0.5
            THEN 'Above average — high value for their region'
        WHEN (us.avg_spend - ra.country_avg_spend) /
             NULLIF(ra.country_spend_stddev, 0) >= -0.5
            THEN 'Average spender for their region'
        ELSE 'Below regional average — price sensitive segment'
    END AS regional_value_tier
FROM user_spend us
JOIN regional_averages ra ON us.country = ra.country
ORDER BY spend_z_score DESC;

-- =====================
-- GEOGRAPHIC EXPANSION OPPORTUNITY SCORING
-- =====================
-- Where should the platform invest in growth next?
-- This combines what we know from actual customer behavior
-- with the market size and growth data from MongoDB
-- to score each market on its expansion attractiveness.
-- High current engagement + large market + high growth
-- = obvious priority. Low engagement + small market + slow growth
-- = deprioritise regardless of how much the team likes the idea.

SELECT
    u.country,
    COUNT(DISTINCT u.user_id) AS current_customers,
    ROUND(AVG(p.price_paid), 2) AS avg_order_value,
    ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_satisfaction,
    -- Market size from MongoDB market_trends (joined by reference)
    CASE u.country
        WHEN 'UAE'      THEN 847
        WHEN 'Pakistan' THEN 156
        WHEN 'UK'       THEN 1200
        WHEN 'Ireland'  THEN 312
        WHEN 'USA'      THEN 8420
        ELSE 50
    END AS market_size_usd_millions,
    -- Growth rate from MongoDB
    CASE u.country
        WHEN 'UAE'      THEN 12.4
        WHEN 'Pakistan' THEN 8.2
        WHEN 'UK'       THEN 5.8
        WHEN 'Ireland'  THEN 5.1
        WHEN 'USA'      THEN 6.8
        ELSE 3.0
    END AS market_growth_percent,
    -- Composite expansion score
    -- Weighted: market size 35%, growth rate 35%,
    -- current satisfaction 20%, avg order value 10%
    ROUND(
        (CASE u.country
            WHEN 'UAE'      THEN 847
            WHEN 'Pakistan' THEN 156
            WHEN 'UK'       THEN 1200
            WHEN 'Ireland'  THEN 312
            WHEN 'USA'      THEN 8420
            ELSE 50
         END / 100.0 * 0.35) +
        (CASE u.country
            WHEN 'UAE'      THEN 12.4
            WHEN 'Pakistan' THEN 8.2
            WHEN 'UK'       THEN 5.8
            WHEN 'Ireland'  THEN 5.1
            WHEN 'USA'      THEN 6.8
            ELSE 3.0
         END * 0.35) +
        (COALESCE(AVG(r.score), 5) * 0.20) +
        (AVG(p.price_paid) / 10.0 * 0.10),
        2
    ) AS expansion_score,
    CASE
        WHEN (CASE u.country
                WHEN 'USA' THEN 8420
                WHEN 'UK' THEN 1200
                ELSE 500
              END) > 1000
            THEN 'Priority market — large addressable base'
        WHEN (CASE u.country
                WHEN 'UAE'      THEN 12.4
                WHEN 'Pakistan' THEN 8.2
                ELSE 5.0
              END) >= 10
            THEN 'Growth market — high momentum, invest now'
        ELSE 'Maintain presence — monitor for shifts'
    END AS expansion_recommendation
FROM users u
LEFT JOIN purchases p ON u.user_id = p.user_id
LEFT JOIN ratings r ON u.user_id = r.user_id
GROUP BY u.country
ORDER BY expansion_score DESC;