-- ScentDB: Product Analytics
-- =====================
-- Product analytics is the discipline of understanding how
-- people actually interact with your catalog — not how you
-- wish they would, not how your marketing says they do,
-- but what the behavioral data actually shows.
--
-- The fragrance market has a specific challenge that makes
-- product analytics here more interesting than most categories.
-- People cannot smell through a screen. Every purchase is
-- made on incomplete information — a description, a review,
-- a recommendation from someone they trust. That gap between
-- discovery and decision creates a funnel with real friction
-- at every stage, and that friction shows up in the data
-- if you build the right queries to find it.
--
-- This file covers the full product analytics toolkit:
-- funnel analysis, catalog performance, engagement scoring,
-- search-to-purchase patterns, and new product launch tracking.
-- These are the reports a product team runs every week.
-- Knowing how to build them from scratch rather than just
-- read a pre-built dashboard is what separates someone who
-- understands data from someone who just consumes it.
-- =====================

-- =====================
-- DISCOVERY TO PURCHASE FUNNEL
-- =====================
-- Every customer journey on ScentDB moves through stages:
-- they discover a fragrance, they consider it (wishlist),
-- and they either buy it or abandon it.
-- Funnel analysis measures the drop-off at each stage.
-- A big drop from wishlist to purchase usually means
-- price friction. A big drop from catalog to wishlist
-- means discovery or relevance problems.
-- Neither problem gets fixed until someone measures it.

WITH funnel_data AS (
    SELECT
        f.fragrance_id,
        f.name AS fragrance,
        b.name AS brand,
        f.price_usd,
        -- Stage 1: Is it in the catalog? (always yes by definition)
        1 AS in_catalog,
        -- Stage 2: Has anyone wishlisted it?
        CASE WHEN COUNT(DISTINCT w.wishlist_id) > 0 THEN 1 ELSE 0 END
            AS has_wishlist,
        -- Stage 3: Has anyone rated it? (shows post-purchase engagement)
        CASE WHEN COUNT(DISTINCT r.rating_id) > 0 THEN 1 ELSE 0 END
            AS has_rating,
        -- Stage 4: Has anyone purchased it?
        CASE WHEN COUNT(DISTINCT p.purchase_id) > 0 THEN 1 ELSE 0 END
            AS has_purchase,
        -- Raw counts for each stage
        COUNT(DISTINCT w.wishlist_id) AS wishlist_count,
        COUNT(DISTINCT p.purchase_id) AS purchase_count,
        COUNT(DISTINCT r.rating_id) AS rating_count
    FROM fragrances f
    JOIN brands b ON f.brand_id = b.brand_id
    LEFT JOIN wishlists w ON f.fragrance_id = w.fragrance_id
    LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
    LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
    GROUP BY f.fragrance_id, f.name, b.name, f.price_usd
)
SELECT
    fragrance,
    brand,
    price_usd,
    wishlist_count AS stage_2_wishlist,
    purchase_count AS stage_3_purchase,
    rating_count AS stage_4_rated,
    -- Conversion rates between stages
    CASE
        WHEN wishlist_count > 0
        THEN ROUND(purchase_count::DECIMAL / wishlist_count * 100, 1)
        ELSE 0
    END AS wishlist_to_purchase_percent,
    CASE
        WHEN purchase_count > 0
        THEN ROUND(rating_count::DECIMAL / purchase_count * 100, 1)
        ELSE 0
    END AS purchase_to_rating_percent,
    -- Overall funnel health verdict
    CASE
        WHEN purchase_count >= 2 AND rating_count >= 1
            THEN 'Healthy funnel'
        WHEN wishlist_count >= 2 AND purchase_count = 0
            THEN 'Wishlist trap — consider price reduction'
        WHEN purchase_count >= 1 AND rating_count = 0
            THEN 'Silent buyers — encourage review submission'
        WHEN wishlist_count = 0 AND purchase_count = 0
            THEN 'No engagement — visibility problem'
        ELSE 'Early stage — monitor'
    END AS funnel_status
FROM funnel_data
ORDER BY purchase_count DESC, wishlist_count DESC;

-- =====================
-- CATALOG PERFORMANCE MATRIX
-- =====================
-- Not every product in a catalog deserves equal attention.
-- The classic BCG matrix from business strategy maps products
-- onto a grid of market share vs growth. Here we build
-- something more grounded in actual behavioral data:
-- engagement (wishlist + rating activity) vs conversion
-- (actual purchases). The four quadrants tell you what to
-- do with each fragrance without having to think too hard.

WITH catalog_metrics AS (
    SELECT
        f.fragrance_id,
        f.name AS fragrance,
        b.name AS brand,
        f.price_usd,
        COUNT(DISTINCT p.purchase_id) AS purchases,
        COUNT(DISTINCT w.wishlist_id) AS wishlists,
        COUNT(DISTINCT r.rating_id) AS ratings,
        ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_rating,
        -- Engagement score: combined signal of interest
        COUNT(DISTINCT w.wishlist_id) + COUNT(DISTINCT r.rating_id) AS engagement
    FROM fragrances f
    JOIN brands b ON f.brand_id = b.brand_id
    LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
    LEFT JOIN wishlists w ON f.fragrance_id = w.fragrance_id
    LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
    GROUP BY f.fragrance_id, f.name, b.name, f.price_usd
),
averages AS (
    SELECT
        AVG(purchases) AS avg_purchases,
        AVG(engagement) AS avg_engagement
    FROM catalog_metrics
)
SELECT
    cm.fragrance,
    cm.brand,
    cm.price_usd,
    cm.purchases,
    cm.engagement,
    cm.avg_rating,
    -- BCG-style quadrant classification
    CASE
        WHEN cm.purchases >= av.avg_purchases
             AND cm.engagement >= av.avg_engagement
            THEN 'Star — high conversion, high engagement. Protect and invest.'
        WHEN cm.purchases >= av.avg_purchases
             AND cm.engagement < av.avg_engagement
            THEN 'Cash Cow — converts well but quietly. Maintain, do not over-invest.'
        WHEN cm.purchases < av.avg_purchases
             AND cm.engagement >= av.avg_engagement
            THEN 'Question Mark — lots of interest but not converting. Fix the friction.'
        ELSE
            'Dog — low engagement, low conversion. Reconsider catalog position.'
    END AS product_quadrant,
    CASE
        WHEN cm.purchases >= av.avg_purchases
             AND cm.engagement >= av.avg_engagement
            THEN 'Feature in homepage and recommendation engine'
        WHEN cm.purchases >= av.avg_purchases
             AND cm.engagement < av.avg_engagement
            THEN 'Keep visible, use in cross-sell bundles'
        WHEN cm.purchases < av.avg_purchases
             AND cm.engagement >= av.avg_engagement
            THEN 'A/B test price point or add social proof'
        ELSE
            'Reduce prominence or run clearance promotion'
    END AS recommended_action
FROM catalog_metrics cm
CROSS JOIN averages av
ORDER BY cm.purchases DESC, cm.engagement DESC;

-- =====================
-- USER ENGAGEMENT SCORING
-- =====================
-- Not all users are equally valuable and not all valuable
-- users look the same. Some buy a lot but never review.
-- Some review extensively but buy infrequently.
-- Some wishlist constantly but rarely pull the trigger.
-- This query builds a composite engagement score that
-- captures the full picture of how involved each user
-- actually is with the platform.

WITH user_engagement AS (
    SELECT
        u.user_id,
        u.username,
        u.country,
        u.joined_date,
        -- Behavioral signals
        COUNT(DISTINCT p.purchase_id) AS total_purchases,
        COUNT(DISTINCT r.rating_id) AS total_ratings,
        COUNT(DISTINCT w.wishlist_id) AS wishlist_items,
        COALESCE(SUM(p.price_paid), 0) AS total_spent,
        COALESCE(AVG(r.score), 0) AS avg_rating_given,
        -- Recency signal
        EXTRACT(DAY FROM (
            CURRENT_DATE - MAX(p.purchase_date)
        ))::INT AS days_since_last_purchase,
        -- Review generosity
        CASE
            WHEN COUNT(DISTINCT p.purchase_id) > 0
            THEN ROUND(
                COUNT(DISTINCT r.rating_id)::DECIMAL /
                COUNT(DISTINCT p.purchase_id) * 100,
                1
            )
            ELSE 0
        END AS review_rate_percent
    FROM users u
    LEFT JOIN purchases p ON u.user_id = p.user_id
    LEFT JOIN ratings r ON u.user_id = r.user_id
    LEFT JOIN wishlists w ON u.user_id = w.user_id
    GROUP BY u.user_id, u.username, u.country, u.joined_date
)
SELECT
    username,
    country,
    total_purchases,
    total_ratings,
    wishlist_items,
    ROUND(total_spent, 2) AS total_spent,
    ROUND(avg_rating_given, 2) AS avg_rating_given,
    review_rate_percent,
    days_since_last_purchase,
    -- Composite engagement score out of 100
    ROUND(
        (LEAST(total_purchases * 15, 30)) +   -- up to 30 pts for buying
        (LEAST(total_ratings * 10, 25)) +      -- up to 25 pts for reviewing
        (LEAST(wishlist_items * 5, 15)) +       -- up to 15 pts for wishlisting
        (LEAST(total_spent / 50, 20)) +         -- up to 20 pts for spending
        (CASE
            WHEN days_since_last_purchase <= 30  THEN 10
            WHEN days_since_last_purchase <= 60  THEN 7
            WHEN days_since_last_purchase <= 90  THEN 4
            ELSE 1
         END),                                  -- up to 10 pts for recency
        1
    ) AS engagement_score,
    CASE
        WHEN ROUND(
            (LEAST(total_purchases * 15, 30)) +
            (LEAST(total_ratings * 10, 25)) +
            (LEAST(wishlist_items * 5, 15)) +
            (LEAST(total_spent / 50, 20)) +
            (CASE
                WHEN days_since_last_purchase <= 30  THEN 10
                WHEN days_since_last_purchase <= 60  THEN 7
                WHEN days_since_last_purchase <= 90  THEN 4
                ELSE 1
             END), 1) >= 70 THEN 'Highly Engaged'
        WHEN ROUND(
            (LEAST(total_purchases * 15, 30)) +
            (LEAST(total_ratings * 10, 25)) +
            (LEAST(wishlist_items * 5, 15)) +
            (LEAST(total_spent / 50, 20)) +
            (CASE
                WHEN days_since_last_purchase <= 30  THEN 10
                WHEN days_since_last_purchase <= 60  THEN 7
                WHEN days_since_last_purchase <= 90  THEN 4
                ELSE 1
             END), 1) >= 40 THEN 'Moderately Engaged'
        ELSE 'Low Engagement'
    END AS engagement_tier
FROM user_engagement
ORDER BY engagement_score DESC;

-- =====================
-- NEW PRODUCT LAUNCH TRACKING
-- =====================
-- When a new fragrance enters the catalog how quickly
-- does it gain traction? Early velocity matters because
-- it determines whether the algorithm surfaces it to
-- more users or lets it sink quietly.
-- This query tracks the first 90 days of each fragrance
-- in the catalog and flags ones that are gaining momentum
-- versus ones that launched flat and stayed there.

WITH fragrance_launch AS (
    SELECT
        f.fragrance_id,
        f.name AS fragrance,
        b.name AS brand,
        f.price_usd,
        f.release_year,
        -- First purchase date as proxy for platform launch
        MIN(p.purchase_date) AS first_sale_date,
        MAX(p.purchase_date) AS most_recent_sale,
        COUNT(p.purchase_id) AS total_purchases,
        COUNT(DISTINCT p.user_id) AS unique_buyers
    FROM fragrances f
    JOIN brands b ON f.brand_id = b.brand_id
    LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
    GROUP BY f.fragrance_id, f.name, b.name, f.price_usd, f.release_year
),
launch_with_velocity AS (
    SELECT
        fragrance,
        brand,
        price_usd,
        release_year,
        first_sale_date,
        most_recent_sale,
        total_purchases,
        unique_buyers,
        -- Days from first sale to most recent
        COALESCE(
            EXTRACT(DAY FROM (most_recent_sale - first_sale_date))::INT,
            0
        ) AS days_on_market,
        -- Purchase velocity: purchases per week
        CASE
            WHEN most_recent_sale IS NOT NULL AND
                 most_recent_sale != first_sale_date
            THEN ROUND(
                total_purchases::DECIMAL /
                GREATEST(
                    EXTRACT(DAY FROM (most_recent_sale - first_sale_date)) / 7.0,
                    1
                ),
                2
            )
            ELSE total_purchases::DECIMAL
        END AS purchases_per_week
    FROM fragrance_launch
)
SELECT
    fragrance,
    brand,
    price_usd,
    release_year,
    first_sale_date,
    total_purchases,
    unique_buyers,
    days_on_market,
    purchases_per_week,
    CASE
        WHEN purchases_per_week >= 1 AND unique_buyers >= 2
            THEN 'Strong launch — gaining traction quickly'
        WHEN purchases_per_week >= 0.5
            THEN 'Steady launch — normal adoption curve'
        WHEN total_purchases >= 1 AND purchases_per_week < 0.3
            THEN 'Slow burn — may need promotional support'
        WHEN total_purchases = 0
            THEN 'No sales yet — needs visibility'
        ELSE 'Monitor'
    END AS launch_status
FROM launch_with_velocity
ORDER BY purchases_per_week DESC;

-- =====================
-- CROSS SELL AND UPSELL OPPORTUNITIES
-- =====================
-- Cross sell: get a customer to buy something they do not
-- already have. Upsell: get them to buy a more expensive
-- version of something they already like.
-- Both require knowing what they own and what they have
-- shown interest in — which is exactly what this database
-- was built to answer.

-- Cross sell: what are users most likely to buy next
-- based on what similar users bought after their first purchase?
WITH user_first_purchase AS (
    SELECT
        user_id,
        fragrance_id AS first_fragrance,
        purchase_date AS first_date
    FROM (
        SELECT
            user_id,
            fragrance_id,
            purchase_date,
            ROW_NUMBER() OVER (
                PARTITION BY user_id ORDER BY purchase_date ASC
            ) AS rn
        FROM purchases
    ) ranked
    WHERE rn = 1
),
second_purchases AS (
    SELECT
        p.user_id,
        ufp.first_fragrance,
        p.fragrance_id AS second_fragrance,
        p.purchase_date
    FROM purchases p
    JOIN user_first_purchase ufp ON p.user_id = ufp.user_id
    WHERE p.fragrance_id != ufp.first_fragrance
    AND p.purchase_date > ufp.first_date
)
SELECT
    f1.name AS if_they_bought,
    f2.name AS they_often_also_buy,
    b2.name AS brand,
    f2.price_usd,
    COUNT(*) AS times_this_pair_occurred
FROM second_purchases sp
JOIN fragrances f1 ON sp.first_fragrance = f1.fragrance_id
JOIN fragrances f2 ON sp.second_fragrance = f2.fragrance_id
JOIN brands b2 ON f2.brand_id = b2.brand_id
GROUP BY f1.name, f2.name, b2.name, f2.price_usd
HAVING COUNT(*) >= 1
ORDER BY times_this_pair_occurred DESC;

-- Upsell: users currently in the accessible tier who have
-- shown high engagement — prime candidates for premium introduction
SELECT
    u.username,
    u.country,
    ROUND(AVG(p.price_paid), 2) AS current_avg_spend,
    MAX(p.price_paid) AS highest_single_purchase,
    ROUND(AVG(r.score), 2) AS avg_rating_given,
    COUNT(w.wishlist_id) AS wishlist_items,
    -- What is the most expensive thing on their wishlist?
    MAX(wf.price_usd) AS most_expensive_wishlisted,
    CASE
        WHEN MAX(wf.price_usd) > AVG(p.price_paid) * 1.5
            THEN 'Aspiring up — wishlist reveals higher price tolerance'
        WHEN AVG(r.score) >= 8 AND AVG(p.price_paid) < 150
            THEN 'Engaged accessible buyer — ready for premium introduction'
        ELSE 'Content at current tier'
    END AS upsell_opportunity
FROM users u
JOIN purchases p ON u.user_id = p.user_id
LEFT JOIN ratings r ON u.user_id = r.user_id
LEFT JOIN wishlists w ON u.user_id = w.user_id
LEFT JOIN fragrances wf ON w.fragrance_id = wf.fragrance_id
GROUP BY u.user_id, u.username, u.country
HAVING AVG(p.price_paid) < 200
ORDER BY avg_rating_given DESC;