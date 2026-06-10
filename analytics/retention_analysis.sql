-- ScentDB: Retention Analysis
-- =====================
-- Retention is the single most important metric for any
-- subscription or repeat-purchase business. Revenue can look
-- healthy while the underlying customer base quietly erodes.
-- New customers replace churned ones on the surface and
-- everything seems fine until acquisition costs rise or
-- a competitor appears and the replacement pipeline dries up.
--
-- The fragrance market is particularly interesting here
-- because purchase cycles are long and irregular. Someone
-- who buys once every six months is not churning — that
-- might just be how they shop. Someone who bought three
-- times in a month and then went silent for four months
-- probably is churning. Treating both the same way leads
-- to campaigns that annoy loyal customers and miss actual
-- at-risk ones.
--
-- This file builds a retention framework that accounts for
-- that irregularity. Rather than using a fixed 90-day churn
-- window for everyone, it calculates each customer's personal
-- purchase rhythm and defines churn relative to their own
-- normal behavior. That approach is more complex to build
-- but significantly more accurate in practice.
--
-- The framework has six components:
-- 1. Purchase rhythm baseline per customer
-- 2. Churn risk scoring relative to personal baseline
-- 3. Customer health index combining multiple signals
-- 4. Reactivation probability for already-churned customers
-- 5. Retention curve showing when customers typically drop off
-- 6. Intervention timing recommendations per customer segment
--
-- Every component here maps to something a retention analyst
-- or CRM manager would actually use. This is not academic —
-- these are the reports that drive the emails you receive
-- from platforms after you have not logged in for a while.
-- =====================

-- =====================
-- COMPONENT 1: PERSONAL PURCHASE RHYTHM
-- =====================
-- Before you can know if someone is overdue for a purchase
-- you need to know what their normal cadence looks like.
-- A customer who buys every 90 days is not at risk at day 91.
-- A customer who buys every 14 days absolutely is.
-- This query establishes the baseline for every customer
-- who has made more than one purchase.

WITH purchase_gaps AS (
    SELECT
        p.user_id,
        u.username,
        p.purchase_date,
        -- Days between this purchase and the previous one
        p.purchase_date - LAG(p.purchase_date) OVER (
            PARTITION BY p.user_id
            ORDER BY p.purchase_date ASC
        ) AS days_since_previous_purchase
    FROM purchases p
    JOIN users u ON p.user_id = u.user_id
)
SELECT
    user_id,
    username,
    COUNT(*) AS total_purchases,
    -- Average days between purchases is their personal rhythm
    ROUND(AVG(days_since_previous_purchase), 0)
        AS avg_days_between_purchases,
    MIN(days_since_previous_purchase)
        AS fastest_repurchase_days,
    MAX(days_since_previous_purchase)
        AS slowest_repurchase_days,
    -- Standard deviation tells you how consistent they are
    ROUND(STDDEV(days_since_previous_purchase), 0)
        AS rhythm_consistency_stddev,
    CASE
        WHEN STDDEV(days_since_previous_purchase) < 15
            THEN 'Very consistent buyer — predictable rhythm'
        WHEN STDDEV(days_since_previous_purchase) < 45
            THEN 'Somewhat consistent — rhythm exists with variation'
        ELSE 'Irregular buyer — no strong rhythm detected'
    END AS rhythm_type
FROM purchase_gaps
WHERE days_since_previous_purchase IS NOT NULL
GROUP BY user_id, username
HAVING COUNT(*) >= 1
ORDER BY avg_days_between_purchases ASC;

-- =====================
-- COMPONENT 2: CHURN RISK SCORING
-- =====================
-- With the personal rhythm established, we can now score
-- each customer's churn risk relative to their own baseline
-- rather than a one-size-fits-all cutoff.
-- A customer who is 1.5x their normal interval overdue
-- is showing early warning signs. At 2x they are at risk.
-- At 3x they have probably already mentally churned even
-- if they have not been formally classified as lost yet.

WITH customer_rhythm AS (
    SELECT
        p.user_id,
        COUNT(*) AS total_purchases,
        AVG(
            p.purchase_date - LAG(p.purchase_date) OVER (
                PARTITION BY p.user_id
                ORDER BY p.purchase_date ASC
            )
        ) AS avg_gap_days,
        MAX(p.purchase_date) AS last_purchase_date
    FROM purchases p
    GROUP BY p.user_id
    HAVING COUNT(*) >= 1
),
churn_scoring AS (
    SELECT
        cr.user_id,
        u.username,
        u.email,
        u.country,
        cr.total_purchases,
        cr.last_purchase_date,
        COALESCE(cr.avg_gap_days, 999) AS personal_avg_gap,
        EXTRACT(DAY FROM (
            CURRENT_DATE - cr.last_purchase_date
        ))::INT AS days_since_last_purchase,
        -- How many times their normal gap has passed without a purchase?
        ROUND(
            EXTRACT(DAY FROM (CURRENT_DATE - cr.last_purchase_date)) /
            NULLIF(cr.avg_gap_days, 0),
            2
        ) AS gap_multiplier
    FROM customer_rhythm cr
    JOIN users u ON cr.user_id = u.user_id
)
SELECT
    username,
    email,
    country,
    total_purchases,
    last_purchase_date,
    days_since_last_purchase,
    ROUND(personal_avg_gap, 0) AS their_normal_gap_days,
    gap_multiplier AS times_overdue,
    -- Churn risk score from 0 to 100
    LEAST(
        ROUND(gap_multiplier * 33.3, 0),
        100
    )::INT AS churn_risk_score,
    CASE
        WHEN gap_multiplier < 1.0
            THEN 'Active — within normal purchase window'
        WHEN gap_multiplier < 1.5
            THEN 'Watch — slightly overdue, monitor closely'
        WHEN gap_multiplier < 2.0
            THEN 'At Risk — meaningfully past their normal rhythm'
        WHEN gap_multiplier < 3.0
            THEN 'High Risk — significantly overdue, intervene now'
        ELSE 'Critical — likely churned, reactivation campaign needed'
    END AS churn_risk_category,
    -- When should we reach out based on their rhythm?
    (cr.last_purchase_date + ROUND(personal_avg_gap, 0)::INT)
        AS predicted_next_purchase_date,
    CASE
        WHEN gap_multiplier >= 2.0
            THEN 'Immediate outreach needed'
        WHEN gap_multiplier >= 1.5
            THEN 'Schedule outreach within 7 days'
        WHEN gap_multiplier >= 1.0
            THEN 'Add to monitoring list'
        ELSE 'No action needed — still in window'
    END AS recommended_action
FROM churn_scoring cr
JOIN customer_rhythm cr2 ON cr.user_id = cr2.user_id
ORDER BY churn_risk_score DESC;

-- =====================
-- COMPONENT 3: CUSTOMER HEALTH INDEX
-- =====================
-- Churn risk looks backward — how long since they last bought?
-- The customer health index looks at the full picture:
-- recent activity, engagement depth, spending trend,
-- satisfaction signals, and relationship length.
-- A customer who has not bought recently but rates everything
-- highly and has a large wishlist is very different from one
-- who is silent across every dimension.
-- The health index captures that nuance in a single number.

WITH customer_signals AS (
    SELECT
        u.user_id,
        u.username,
        u.country,
        u.joined_date,
        -- Recency signal (0-25 points)
        CASE
            WHEN MAX(p.purchase_date) >= CURRENT_DATE - 30
                THEN 25
            WHEN MAX(p.purchase_date) >= CURRENT_DATE - 60
                THEN 18
            WHEN MAX(p.purchase_date) >= CURRENT_DATE - 90
                THEN 10
            WHEN MAX(p.purchase_date) IS NOT NULL
                THEN 4
            ELSE 0
        END AS recency_score,
        -- Frequency signal (0-25 points)
        LEAST(COUNT(DISTINCT p.purchase_id) * 8, 25)
            AS frequency_score,
        -- Monetary signal (0-25 points)
        LEAST(ROUND(COALESCE(SUM(p.price_paid), 0) / 20, 0), 25)::INT
            AS monetary_score,
        -- Engagement signal: reviews and wishlists (0-15 points)
        LEAST(
            COUNT(DISTINCT r.rating_id) * 4 +
            COUNT(DISTINCT w.wishlist_id) * 2,
            15
        ) AS engagement_score,
        -- Satisfaction signal: average rating given (0-10 points)
        ROUND(COALESCE(AVG(r.score), 5) - 5, 0)::INT
            AS satisfaction_score,
        -- Raw metrics for context
        COUNT(DISTINCT p.purchase_id) AS total_purchases,
        ROUND(COALESCE(SUM(p.price_paid), 0), 2) AS total_spent,
        ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_rating_given,
        COUNT(DISTINCT r.rating_id) AS total_reviews,
        COUNT(DISTINCT w.wishlist_id) AS wishlist_items,
        MAX(p.purchase_date) AS last_purchase_date
    FROM users u
    LEFT JOIN purchases p ON u.user_id = p.user_id
    LEFT JOIN ratings r ON u.user_id = r.user_id
    LEFT JOIN wishlists w ON u.user_id = w.user_id
    GROUP BY u.user_id, u.username, u.country, u.joined_date
)
SELECT
    username,
    country,
    joined_date,
    last_purchase_date,
    total_purchases,
    total_spent,
    avg_rating_given,
    total_reviews,
    wishlist_items,
    recency_score,
    frequency_score,
    monetary_score,
    engagement_score,
    satisfaction_score,
    -- Combined health index out of 100
    recency_score + frequency_score + monetary_score +
    engagement_score + GREATEST(satisfaction_score, 0)
        AS health_index,
    CASE
        WHEN recency_score + frequency_score + monetary_score +
             engagement_score + GREATEST(satisfaction_score, 0) >= 75
            THEN 'Thriving — highly engaged, high value customer'
        WHEN recency_score + frequency_score + monetary_score +
             engagement_score + GREATEST(satisfaction_score, 0) >= 50
            THEN 'Healthy — active and engaged, worth nurturing'
        WHEN recency_score + frequency_score + monetary_score +
             engagement_score + GREATEST(satisfaction_score, 0) >= 30
            THEN 'Declining — showing warning signs across signals'
        WHEN recency_score + frequency_score + monetary_score +
             engagement_score + GREATEST(satisfaction_score, 0) >= 15
            THEN 'At Risk — multiple signals pointing to churn'
        ELSE 'Critical — immediate retention intervention needed'
    END AS health_status
FROM customer_signals
ORDER BY health_index DESC;

-- =====================
-- COMPONENT 4: REACTIVATION PROBABILITY
-- =====================
-- Some customers who stop buying can be brought back.
-- Others are gone for good and chasing them wastes budget
-- that could go toward retaining customers who are still
-- engaged. Reactivation probability estimates which churned
-- customers are worth the effort based on their historical
-- behavior before they went silent.
--
-- The logic: a customer who bought frequently, spent well,
-- and engaged deeply before going silent is more likely to
-- respond to a reactivation campaign than one who made a
-- single purchase, never reviewed, and never wishlisted again.
-- Past behavior is the best predictor of future behavior
-- even when there has been a gap.

WITH churned_customers AS (
    SELECT
        u.user_id,
        u.username,
        u.email,
        u.country,
        COUNT(DISTINCT p.purchase_id) AS lifetime_purchases,
        ROUND(SUM(p.price_paid), 2) AS lifetime_spend,
        ROUND(AVG(p.price_paid), 2) AS avg_order_value,
        MAX(p.purchase_date) AS last_purchase_date,
        EXTRACT(DAY FROM (
            CURRENT_DATE - MAX(p.purchase_date)
        ))::INT AS days_silent,
        COUNT(DISTINCT r.rating_id) AS total_reviews,
        ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_rating,
        COUNT(DISTINCT w.wishlist_id) AS wishlist_items
    FROM users u
    JOIN purchases p ON u.user_id = p.user_id
    LEFT JOIN ratings r ON u.user_id = r.user_id
    LEFT JOIN wishlists w ON u.user_id = w.user_id
    GROUP BY u.user_id, u.username, u.email, u.country
    -- Define churned as no purchase in 90+ days
    HAVING MAX(p.purchase_date) < CURRENT_DATE - 90
)
SELECT
    username,
    email,
    country,
    lifetime_purchases,
    lifetime_spend,
    avg_order_value,
    last_purchase_date,
    days_silent,
    total_reviews,
    avg_rating,
    wishlist_items,
    -- Reactivation probability score out of 100
    ROUND(
        -- High historical spend is the strongest signal
        (LEAST(lifetime_spend / 10, 30)) +
        -- Multiple purchases shows genuine attachment
        (LEAST(lifetime_purchases * 8, 25)) +
        -- Reviews show emotional investment in the platform
        (LEAST(total_reviews * 7, 21)) +
        -- Wishlist items show future intent even while silent
        (LEAST(wishlist_items * 6, 12)) +
        -- High average rating shows satisfaction before churn
        (CASE WHEN avg_rating >= 8 THEN 12
              WHEN avg_rating >= 6 THEN 7
              ELSE 2 END),
        0
    )::INT AS reactivation_probability,
    CASE
        WHEN ROUND(
            (LEAST(lifetime_spend / 10, 30)) +
            (LEAST(lifetime_purchases * 8, 25)) +
            (LEAST(total_reviews * 7, 21)) +
            (LEAST(wishlist_items * 6, 12)) +
            (CASE WHEN avg_rating >= 8 THEN 12
                  WHEN avg_rating >= 6 THEN 7
                  ELSE 2 END),
            0
        ) >= 60
            THEN 'High probability — personalised win-back worth investing in'
        WHEN ROUND(
            (LEAST(lifetime_spend / 10, 30)) +
            (LEAST(lifetime_purchases * 8, 25)) +
            (LEAST(total_reviews * 7, 21)) +
            (LEAST(wishlist_items * 6, 12)) +
            (CASE WHEN avg_rating >= 8 THEN 12
                  WHEN avg_rating >= 6 THEN 7
                  ELSE 2 END),
            0
        ) >= 35
            THEN 'Moderate probability — standard win-back campaign'
        ELSE 'Low probability — last chance email only, then sunset'
    END AS reactivation_strategy,
    -- What to offer based on their history
    CASE
        WHEN avg_order_value >= 300
            THEN 'Offer: exclusive early access to new premium launches'
        WHEN avg_order_value >= 150
            THEN 'Offer: 15% discount on their most wishlisted fragrance'
        ELSE
            'Offer: free sample with next purchase over $80'
    END AS recommended_offer
FROM churned_customers
ORDER BY reactivation_probability DESC;

-- =====================
-- COMPONENT 5: RETENTION CURVE
-- =====================
-- At what point in the customer lifecycle do most people
-- stop buying? The retention curve answers this by tracking
-- what percentage of customers made a second purchase,
-- a third, a fourth, and so on.
-- A steep drop between purchase 1 and purchase 2 is the
-- most common pattern and the most actionable one —
-- converting one-time buyers into repeat buyers is usually
-- the highest-leverage retention investment a business can make.

WITH purchase_sequences AS (
    SELECT
        user_id,
        purchase_date,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY purchase_date ASC
        ) AS purchase_number
    FROM purchases
),
sequence_counts AS (
    SELECT
        purchase_number,
        COUNT(DISTINCT user_id) AS customers_reached_this_purchase
    FROM purchase_sequences
    GROUP BY purchase_number
),
total_customers AS (
    SELECT COUNT(DISTINCT user_id) AS n FROM purchases
)
SELECT
    sc.purchase_number,
    sc.customers_reached_this_purchase,
    tc.n AS total_customers,
    -- What percentage of all customers made it to this purchase number?
    ROUND(
        sc.customers_reached_this_purchase::DECIMAL / tc.n * 100,
        1
    ) AS retention_rate_percent,
    -- Drop-off from the previous purchase number
    ROUND(
        (sc.customers_reached_this_purchase -
         LAG(sc.customers_reached_this_purchase) OVER (
             ORDER BY sc.purchase_number ASC
         ))::DECIMAL /
        NULLIF(LAG(sc.customers_reached_this_purchase) OVER (
            ORDER BY sc.purchase_number ASC
        ), 0) * 100,
        1
    ) AS dropoff_from_previous_percent,
    -- Visual bar chart proxy for quick reading
    REPEAT('█', sc.customers_reached_this_purchase) AS visual_bar
FROM sequence_counts sc
CROSS JOIN total_customers tc
ORDER BY sc.purchase_number ASC;

-- =====================
-- COMPONENT 6: INTERVENTION TIMING CALENDAR
-- =====================
-- Knowing a customer is at risk is only useful if you know
-- when to reach out. Too early and it feels like spam.
-- Too late and they have already moved on.
-- This query builds a concrete intervention calendar —
-- specific customers, specific recommended contact dates,
-- specific messaging angles based on their profile.
-- This is the output that feeds directly into a CRM system.

WITH customer_timing AS (
    SELECT
        u.user_id,
        u.username,
        u.email,
        u.country,
        MAX(p.purchase_date) AS last_purchase_date,
        COUNT(DISTINCT p.purchase_id) AS total_purchases,
        ROUND(AVG(p.price_paid), 2) AS avg_spend,
        ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_rating,
        COUNT(DISTINCT w.wishlist_id) AS wishlist_items,
        EXTRACT(DAY FROM (
            CURRENT_DATE - MAX(p.purchase_date)
        ))::INT AS days_since_last_purchase
    FROM users u
    JOIN purchases p ON u.user_id = p.user_id
    LEFT JOIN ratings r ON u.user_id = r.user_id
    LEFT JOIN wishlists w ON u.user_id = w.user_id
    GROUP BY u.user_id, u.username, u.email, u.country
)
SELECT
    username,
    email,
    country,
    last_purchase_date,
    days_since_last_purchase,
    total_purchases,
    avg_spend,
    avg_rating,
    wishlist_items,
    -- Recommended contact date
    CASE
        WHEN days_since_last_purchase >= 120
            THEN CURRENT_DATE
        WHEN days_since_last_purchase >= 90
            THEN CURRENT_DATE + 3
        WHEN days_since_last_purchase >= 60
            THEN CURRENT_DATE + 7
        ELSE CURRENT_DATE + 14
    END AS recommended_contact_date,
    -- Days until recommended contact
    CASE
        WHEN days_since_last_purchase >= 120 THEN 0
        WHEN days_since_last_purchase >= 90  THEN 3
        WHEN days_since_last_purchase >= 60  THEN 7
        ELSE 14
    END AS days_until_contact,
    -- What channel to use
    CASE
        WHEN total_purchases >= 3 AND avg_spend >= 200
            THEN 'Personal email from account manager'
        WHEN total_purchases >= 2
            THEN 'Targeted email campaign'
        ELSE 'Standard re-engagement email'
    END AS contact_channel,
    -- What angle to lead with
    CASE
        WHEN wishlist_items > 0
            THEN 'Lead with wishlist items — they already told us what they want'
        WHEN avg_rating >= 8
            THEN 'Lead with new arrivals similar to their highest rated purchases'
        WHEN avg_spend >= 300
            THEN 'Lead with exclusive access — reward their premium status'
        ELSE 'Lead with a time-limited discount to create urgency'
    END AS message_angle,
    -- Priority tier for the CRM team
    CASE
        WHEN days_since_last_purchase >= 120 AND avg_spend >= 200
            THEN 1
        WHEN days_since_last_purchase >= 90
            THEN 2
        WHEN days_since_last_purchase >= 60
            THEN 3
        ELSE 4
    END AS crm_priority
FROM customer_timing
ORDER BY crm_priority ASC, days_since_last_purchase DESC;