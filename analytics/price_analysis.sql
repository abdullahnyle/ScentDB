-- ScentDB: Price Analysis
-- =====================
-- Pricing is one of those things that looks simple from the outside
-- and turns out to be genuinely complicated the moment you try to
-- optimise it. Charge too much and you lose customers who would
-- have bought at a lower price. Charge too little and you leave
-- money on the table from customers who would have paid more.
--
-- The fragrance market makes this especially interesting because
-- price is not just a cost signal — it is part of the product.
-- A $500 Creed bottle is not just more expensive than a $95 Versace.
-- It means something different to the person wearing it. That
-- psychological dimension shows up in the data if you know where
-- to look for it.
--
-- This file builds a full picture of how price behaves across
-- the ScentDB catalog — which price points convert best, where
-- customers feel they are getting value, where they feel ripped
-- off, and what the data suggests about optimal positioning.
-- These are exactly the questions a business analyst on a retail
-- or e-commerce team gets asked to answer in their first month.
-- =====================

-- =====================
-- PRICE DISTRIBUTION ACROSS THE CATALOG
-- =====================
-- Before you can optimise pricing you need to understand
-- what the current distribution actually looks like.
-- Are most products clustered in one price band?
-- Is there a gap in the mid-range that competitors could exploit?
-- These are strategic questions and the data answers them.

SELECT
    CASE
        WHEN price_usd < 100  THEN '1. Under $100 (Accessible)'
        WHEN price_usd < 150  THEN '2. $100–$149 (Entry Luxury)'
        WHEN price_usd < 200  THEN '3. $150–$199 (Mid Luxury)'
        WHEN price_usd < 300  THEN '4. $200–$299 (Premium)'
        WHEN price_usd < 400  THEN '5. $300–$399 (High End)'
        ELSE                       '6. $400+ (Ultra Luxury)'
    END AS price_tier,
    COUNT(*) AS fragrances_in_tier,
    ROUND(AVG(price_usd), 2) AS avg_price,
    MIN(price_usd) AS lowest_price,
    MAX(price_usd) AS highest_price,
    -- What share of the catalog sits in this tier?
    ROUND(COUNT(*)::DECIMAL / (SELECT COUNT(*) FROM fragrances) * 100, 1)
        AS catalog_share_percent
FROM fragrances
GROUP BY
    CASE
        WHEN price_usd < 100  THEN '1. Under $100 (Accessible)'
        WHEN price_usd < 150  THEN '2. $100–$149 (Entry Luxury)'
        WHEN price_usd < 200  THEN '3. $150–$199 (Mid Luxury)'
        WHEN price_usd < 300  THEN '4. $200–$299 (Premium)'
        WHEN price_usd < 400  THEN '5. $300–$399 (High End)'
        ELSE                       '6. $400+ (Ultra Luxury)'
    END
ORDER BY price_tier;

-- =====================
-- PRICE TIER CONVERSION RATES
-- =====================
-- Which price tier actually converts best?
-- Conversion here means: of all the fragrances in a tier,
-- what percentage have at least one purchase recorded?
-- A tier with high catalog presence but low conversion
-- tells you something important — either the pricing is wrong,
-- the product is wrong, or the marketing is wrong.
-- The data cannot tell you which. But it tells you where to look.

WITH tier_data AS (
    SELECT
        f.fragrance_id,
        f.name,
        f.price_usd,
        CASE
            WHEN f.price_usd < 100  THEN '1. Under $100'
            WHEN f.price_usd < 150  THEN '2. $100–$149'
            WHEN f.price_usd < 200  THEN '3. $150–$199'
            WHEN f.price_usd < 300  THEN '4. $200–$299'
            WHEN f.price_usd < 400  THEN '5. $300–$399'
            ELSE                         '6. $400+'
        END AS price_tier,
        COUNT(DISTINCT p.purchase_id) AS purchase_count,
        COUNT(DISTINCT r.rating_id) AS rating_count,
        COUNT(DISTINCT w.wishlist_id) AS wishlist_count,
        ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_rating
    FROM fragrances f
    LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
    LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
    LEFT JOIN wishlists w ON f.fragrance_id = w.fragrance_id
    GROUP BY f.fragrance_id, f.name, f.price_usd
)
SELECT
    price_tier,
    COUNT(*) AS total_fragrances,
    SUM(CASE WHEN purchase_count > 0 THEN 1 ELSE 0 END)
        AS fragrances_with_purchases,
    ROUND(
        SUM(CASE WHEN purchase_count > 0 THEN 1 ELSE 0 END)::DECIMAL /
        NULLIF(COUNT(*), 0) * 100,
        1
    ) AS conversion_rate_percent,
    ROUND(AVG(avg_rating), 2) AS avg_rating_in_tier,
    SUM(purchase_count) AS total_purchases,
    SUM(wishlist_count) AS total_wishlists,
    -- Wishlist to purchase ratio
    -- High ratio means demand exists but something blocks the purchase
    -- Usually price, availability, or indecision
    ROUND(
        SUM(wishlist_count)::DECIMAL /
        NULLIF(SUM(purchase_count), 0),
        2
    ) AS wishlist_to_purchase_ratio
FROM tier_data
GROUP BY price_tier
ORDER BY price_tier;

-- =====================
-- PRICE VS RATING CORRELATION
-- =====================
-- Do more expensive fragrances actually get better ratings?
-- The honest answer in luxury goods is: sometimes yes, sometimes no.
-- What matters is whether customers feel the price is justified
-- after they have experienced the product.
-- A highly rated cheap fragrance is a hidden gem.
-- A poorly rated expensive one is a liability.

SELECT
    f.name AS fragrance,
    b.name AS brand,
    f.price_usd,
    ROUND(AVG(r.score), 2) AS avg_rating,
    COUNT(r.rating_id) AS review_count,
    COUNT(p.purchase_id) AS purchase_count,
    -- Value score: how good is it relative to its price?
    -- Higher means better value perception
    ROUND(AVG(r.score) / (f.price_usd / 100), 3) AS value_score,
    CASE
        WHEN AVG(r.score) >= 8 AND f.price_usd >= 300
            THEN 'Premium justified — high rating validates the price'
        WHEN AVG(r.score) >= 8 AND f.price_usd < 150
            THEN 'Hidden gem — exceptional quality at accessible price'
        WHEN AVG(r.score) < 7 AND f.price_usd >= 300
            THEN 'Price-quality gap — customers feel overcharged'
        WHEN AVG(r.score) < 7 AND f.price_usd < 150
            THEN 'Underperformer — low price not compensating for quality'
        WHEN AVG(r.score) >= 7 AND f.price_usd BETWEEN 150 AND 299
            THEN 'Solid mid-range — good value, consistent performer'
        ELSE 'Insufficient data for verdict'
    END AS pricing_verdict
FROM fragrances f
JOIN brands b ON f.brand_id = b.brand_id
LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
GROUP BY f.name, b.name, f.price_usd
HAVING COUNT(r.rating_id) > 0
ORDER BY value_score DESC;

-- =====================
-- BRAND PRICING STRATEGY ANALYSIS
-- =====================
-- Every brand has a pricing strategy whether they consciously
-- chose one or not. Some brands own a single price point.
-- Others spread across tiers to capture different segments.
-- Looking at brand-level pricing patterns tells you whether
-- a brand is executing a deliberate strategy or just pricing
-- ad hoc and hoping for the best.

SELECT
    b.name AS brand,
    b.country AS brand_origin,
    COUNT(f.fragrance_id) AS catalog_size,
    MIN(f.price_usd) AS entry_price,
    MAX(f.price_usd) AS ceiling_price,
    ROUND(AVG(f.price_usd), 2) AS avg_price,
    MAX(f.price_usd) - MIN(f.price_usd) AS price_range,
    -- Coefficient of variation: how spread out are their prices?
    -- Low CV = consistent pricing strategy
    -- High CV = broad range targeting multiple segments
    ROUND(
        STDDEV(f.price_usd) / NULLIF(AVG(f.price_usd), 0) * 100,
        1
    ) AS price_variation_percent,
    ROUND(AVG(r.score), 2) AS avg_rating_across_catalog,
    SUM(p.price_paid) AS total_brand_revenue,
    CASE
        WHEN MAX(f.price_usd) - MIN(f.price_usd) < 50
            THEN 'Single tier — consistent price positioning'
        WHEN MAX(f.price_usd) - MIN(f.price_usd) < 200
            THEN 'Narrow range — slight variation within a segment'
        ELSE 'Multi tier — deliberate good/better/best strategy'
    END AS pricing_strategy
FROM brands b
JOIN fragrances f ON b.brand_id = f.brand_id
LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
GROUP BY b.name, b.country
ORDER BY avg_price DESC;

-- =====================
-- DISCOUNT IMPACT SIMULATION
-- =====================
-- What would happen to revenue if we discounted specific
-- price tiers? This is the kind of scenario analysis a
-- commercial team asks for before running a promotion.
-- We cannot observe actual price elasticity without
-- historical price change data, but we can model
-- different demand uplift assumptions and show the
-- revenue impact of each scenario.
-- Showing your work on assumptions is half the job.

WITH current_revenue AS (
    SELECT
        CASE
            WHEN f.price_usd < 100  THEN 'Under $100'
            WHEN f.price_usd < 200  THEN '$100–$199'
            WHEN f.price_usd < 300  THEN '$200–$299'
            ELSE '$300+'
        END AS price_tier,
        COUNT(p.purchase_id) AS current_purchases,
        SUM(p.price_paid) AS current_revenue,
        ROUND(AVG(p.price_paid), 2) AS avg_price_paid
    FROM purchases p
    JOIN fragrances f ON p.fragrance_id = f.fragrance_id
    GROUP BY
        CASE
            WHEN f.price_usd < 100  THEN 'Under $100'
            WHEN f.price_usd < 200  THEN '$100–$199'
            WHEN f.price_usd < 300  THEN '$200–$299'
            ELSE '$300+'
        END
)
SELECT
    price_tier,
    current_purchases,
    ROUND(current_revenue, 2) AS current_revenue,
    -- Scenario A: 10% discount with 20% volume uplift
    ROUND(current_revenue * 0.90 * 1.20, 2) AS scenario_a_revenue,
    ROUND((current_revenue * 0.90 * 1.20) - current_revenue, 2)
        AS scenario_a_impact,
    -- Scenario B: 15% discount with 35% volume uplift
    ROUND(current_revenue * 0.85 * 1.35, 2) AS scenario_b_revenue,
    ROUND((current_revenue * 0.85 * 1.35) - current_revenue, 2)
        AS scenario_b_impact,
    -- Scenario C: 20% discount with 50% volume uplift
    ROUND(current_revenue * 0.80 * 1.50, 2) AS scenario_c_revenue,
    ROUND((current_revenue * 0.80 * 1.50) - current_revenue, 2)
        AS scenario_c_impact,
    -- Which scenario wins for this tier?
    CASE
        WHEN (current_revenue * 0.80 * 1.50) >
             (current_revenue * 0.85 * 1.35) AND
             (current_revenue * 0.80 * 1.50) >
             (current_revenue * 0.90 * 1.20)
            THEN 'Scenario C — aggressive discount wins'
        WHEN (current_revenue * 0.85 * 1.35) >
             (current_revenue * 0.90 * 1.20)
            THEN 'Scenario B — moderate discount wins'
        ELSE 'Scenario A — light discount wins'
    END AS recommended_scenario
FROM current_revenue
ORDER BY current_revenue DESC;

-- =====================
-- PRICE ANCHORING EFFECT
-- =====================
-- Price anchoring is the tendency for customers to evaluate
-- a price relative to something they saw first.
-- Show someone a $500 fragrance and then a $185 one and
-- the second feels reasonable. Show them the $185 first
-- and it feels expensive.
--
-- This query looks for evidence of anchoring in the data —
-- specifically whether users who purchased a high-priced
-- fragrance first went on to spend more overall than users
-- who started with a cheaper one. If they do, anchoring
-- is working and the catalog should lead with premium.

WITH purchase_order AS (
    SELECT
        p.user_id,
        p.fragrance_id,
        p.price_paid,
        p.purchase_date,
        ROW_NUMBER() OVER (
            PARTITION BY p.user_id
            ORDER BY p.purchase_date ASC
        ) AS purchase_sequence,
        SUM(p.price_paid) OVER (
            PARTITION BY p.user_id
        ) AS lifetime_spend
    FROM purchases p
),
first_purchase_analysis AS (
    SELECT
        po.user_id,
        po.price_paid AS first_purchase_price,
        po.lifetime_spend,
        CASE
            WHEN po.price_paid >= 300 THEN 'Started Premium ($300+)'
            WHEN po.price_paid >= 150 THEN 'Started Mid Range ($150–$299)'
            ELSE 'Started Accessible (Under $150)'
        END AS entry_tier
    FROM purchase_order po
    WHERE po.purchase_sequence = 1
)
SELECT
    entry_tier,
    COUNT(user_id) AS users,
    ROUND(AVG(first_purchase_price), 2) AS avg_first_purchase,
    ROUND(AVG(lifetime_spend), 2) AS avg_lifetime_spend,
    ROUND(AVG(lifetime_spend) - AVG(first_purchase_price), 2)
        AS avg_subsequent_spend,
    -- Does starting premium lead to higher total spend?
    ROUND(
        AVG(lifetime_spend) / NULLIF(AVG(first_purchase_price), 0),
        2
    ) AS spend_multiplier
FROM first_purchase_analysis
GROUP BY entry_tier
ORDER BY avg_lifetime_spend DESC;

-- =====================
-- OPTIMAL PRICE POINT RECOMMENDATION
-- =====================
-- Pull everything together into a single recommendation
-- for each fragrance. Is it priced right, too high, or
-- leaving money on the table?
-- This is the executive summary version — one row per
-- fragrance, one clear verdict, one recommended action.

WITH fragrance_performance AS (
    SELECT
        f.fragrance_id,
        f.name,
        b.name AS brand,
        f.price_usd,
        f.concentration,
        COUNT(DISTINCT p.purchase_id) AS purchases,
        COUNT(DISTINCT r.rating_id) AS reviews,
        COUNT(DISTINCT w.wishlist_id) AS wishlists,
        ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_rating,
        ROUND(COALESCE(AVG(r.score), 0) / (f.price_usd / 100), 3)
            AS value_score
    FROM fragrances f
    JOIN brands b ON f.brand_id = b.brand_id
    LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
    LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
    LEFT JOIN wishlists w ON f.fragrance_id = w.fragrance_id
    GROUP BY f.fragrance_id, f.name, b.name, f.price_usd, f.concentration
)
SELECT
    name AS fragrance,
    brand,
    price_usd AS current_price,
    avg_rating,
    purchases,
    wishlists,
    value_score,
    CASE
        WHEN avg_rating >= 9 AND wishlists > purchases
            THEN 'Consider 5–10% price increase — demand exceeds conversion'
        WHEN avg_rating >= 8 AND purchases >= 2
            THEN 'Price is working — maintain and monitor'
        WHEN avg_rating >= 7 AND purchases = 0 AND wishlists > 0
            THEN 'Lower barrier — try limited time discount to convert wishlist'
        WHEN avg_rating < 7 AND price_usd > 200
            THEN 'Price-quality misalignment — quality improvement or price reduction needed'
        WHEN purchases = 0 AND wishlists = 0
            THEN 'No market signal yet — needs visibility before pricing decisions'
        ELSE 'Monitor — insufficient data for confident recommendation'
    END AS pricing_recommendation
FROM fragrance_performance
ORDER BY value_score DESC;