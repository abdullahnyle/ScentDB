-- ScentDB: RFM Analysis
-- =====================
-- RFM stands for Recency, Frequency, Monetary.
-- It is one of the oldest and most reliable frameworks in
-- business analytics — used by every serious retail and
-- e-commerce operation from small boutiques to Amazon.
-- The idea is simple: your best customers bought recently,
-- buy often, and spend the most. Score each customer on
-- all three dimensions and you instantly know who to reward,
-- who to re-engage, and who you've probably already lost.
-- Every business analytics master's program covers this.
-- Building it from scratch on real data is the difference
-- between knowing the concept and being able to use it.
-- =====================

-- =====================
-- STEP 1: RAW RFM METRICS
-- =====================
-- Calculate the three raw numbers for every user
-- before we score or segment them.

WITH rfm_raw AS (
    SELECT
        u.user_id,
        u.username,
        u.country,
        -- Recency: how many days since their last purchase?
        -- Lower is better — a purchase yesterday beats one six months ago
        EXTRACT(DAY FROM (
            CURRENT_DATE - MAX(p.purchase_date)
        ))::INT AS days_since_last_purchase,

        -- Frequency: how many purchases have they made total?
        -- Higher is better
        COUNT(p.purchase_id) AS total_purchases,

        -- Monetary: how much have they spent in total?
        -- Higher is better
        SUM(p.price_paid) AS total_spent,

        -- Supporting context
        MIN(p.purchase_date) AS first_purchase_date,
        MAX(p.purchase_date) AS last_purchase_date,
        AVG(p.price_paid) AS avg_order_value
    FROM users u
    JOIN purchases p ON u.user_id = p.user_id
    GROUP BY u.user_id, u.username, u.country
)
SELECT
    user_id,
    username,
    country,
    days_since_last_purchase AS recency_days,
    total_purchases AS frequency,
    total_spent AS monetary,
    ROUND(avg_order_value, 2) AS avg_order_value,
    first_purchase_date,
    last_purchase_date
FROM rfm_raw
ORDER BY total_spent DESC;

-- =====================
-- STEP 2: RFM SCORING
-- =====================
-- Convert raw numbers into scores from 1 to 5.
-- Score 5 = best, Score 1 = worst.
-- We use NTILE(5) to split users into five equal buckets
-- based on their raw metrics.
-- Note the inversion for recency — lower days = higher score.

WITH rfm_raw AS (
    SELECT
        u.user_id,
        u.username,
        u.country,
        EXTRACT(DAY FROM (
            CURRENT_DATE - MAX(p.purchase_date)
        ))::INT AS recency_days,
        COUNT(p.purchase_id) AS frequency,
        SUM(p.price_paid) AS monetary
    FROM users u
    JOIN purchases p ON u.user_id = p.user_id
    GROUP BY u.user_id, u.username, u.country
),
rfm_scored AS (
    SELECT
        user_id,
        username,
        country,
        recency_days,
        frequency,
        monetary,
        -- Recency score: fewer days = higher score (inverted)
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        -- Frequency score: more purchases = higher score
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        -- Monetary score: more spent = higher score
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_raw
)
SELECT
    user_id,
    username,
    country,
    recency_days,
    frequency,
    ROUND(monetary, 2) AS monetary,
    r_score,
    f_score,
    m_score,
    -- Combined RFM score as a single number
    (r_score + f_score + m_score) AS total_rfm_score,
    -- Combined as a string for segment lookup
    CONCAT(r_score, f_score, m_score) AS rfm_cell
FROM rfm_scored
ORDER BY total_rfm_score DESC;

-- =====================
-- STEP 3: CUSTOMER SEGMENTATION
-- =====================
-- Map RFM scores to human-readable segments.
-- These segments directly inform marketing decisions —
-- Champions get early access and loyalty rewards,
-- At Risk customers get win-back campaigns,
-- Lost customers might not be worth re-engaging at all.

WITH rfm_raw AS (
    SELECT
        u.user_id,
        u.username,
        u.country,
        EXTRACT(DAY FROM (
            CURRENT_DATE - MAX(p.purchase_date)
        ))::INT AS recency_days,
        COUNT(p.purchase_id) AS frequency,
        SUM(p.price_paid) AS monetary
    FROM users u
    JOIN purchases p ON u.user_id = p.user_id
    GROUP BY u.user_id, u.username, u.country
),
rfm_scored AS (
    SELECT
        user_id,
        username,
        country,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_raw
),
rfm_segmented AS (
    SELECT
        user_id,
        username,
        country,
        recency_days,
        frequency,
        ROUND(monetary, 2) AS monetary,
        r_score,
        f_score,
        m_score,
        (r_score + f_score + m_score) AS total_score,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4
                THEN 'Champion'
            WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3
                THEN 'Loyal Customer'
            WHEN r_score >= 4 AND f_score <= 2
                THEN 'New Customer'
            WHEN r_score >= 3 AND f_score >= 2 AND m_score >= 2
                THEN 'Potential Loyalist'
            WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3
                THEN 'At Risk'
            WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4
                THEN 'Cannot Lose Them'
            WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2
                THEN 'Lost'
            WHEN r_score <= 3 AND f_score <= 3
                THEN 'Needs Attention'
            ELSE 'Promising'
        END AS segment
    FROM rfm_scored
)
SELECT
    user_id,
    username,
    country,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    total_score,
    segment
FROM rfm_segmented
ORDER BY total_score DESC;

-- =====================
-- STEP 4: SEGMENT SUMMARY
-- =====================
-- Roll up individual scores into segment-level insights.
-- This is what you'd show in a business review —
-- not individual customers but the health of each segment.

WITH rfm_raw AS (
    SELECT
        u.user_id,
        u.username,
        EXTRACT(DAY FROM (
            CURRENT_DATE - MAX(p.purchase_date)
        ))::INT AS recency_days,
        COUNT(p.purchase_id) AS frequency,
        SUM(p.price_paid) AS monetary
    FROM users u
    JOIN purchases p ON u.user_id = p.user_id
    GROUP BY u.user_id, u.username
),
rfm_scored AS (
    SELECT
        user_id,
        username,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_raw
),
rfm_segmented AS (
    SELECT
        user_id,
        username,
        recency_days,
        frequency,
        monetary,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4
                THEN 'Champion'
            WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3
                THEN 'Loyal Customer'
            WHEN r_score >= 4 AND f_score <= 2
                THEN 'New Customer'
            WHEN r_score >= 3 AND f_score >= 2 AND m_score >= 2
                THEN 'Potential Loyalist'
            WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3
                THEN 'At Risk'
            WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4
                THEN 'Cannot Lose Them'
            WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2
                THEN 'Lost'
            ELSE 'Needs Attention'
        END AS segment
    FROM rfm_scored
)
SELECT
    segment,
    COUNT(user_id) AS customer_count,
    ROUND(AVG(recency_days), 1) AS avg_days_since_purchase,
    ROUND(AVG(frequency), 1) AS avg_purchase_frequency,
    ROUND(AVG(monetary), 2) AS avg_total_spent,
    ROUND(SUM(monetary), 2) AS segment_total_revenue,
    ROUND(SUM(monetary) / SUM(SUM(monetary)) OVER () * 100, 1) AS revenue_share_percent
FROM rfm_segmented
GROUP BY segment
ORDER BY avg_total_spent DESC;

-- =====================
-- STEP 5: ACTIONABLE MARKETING RECOMMENDATIONS
-- =====================
-- The whole point of RFM is to know what to DO next.
-- This query pairs each customer with a specific action.

WITH rfm_raw AS (
    SELECT
        u.user_id,
        u.username,
        u.email,
        EXTRACT(DAY FROM (
            CURRENT_DATE - MAX(p.purchase_date)
        ))::INT AS recency_days,
        COUNT(p.purchase_id) AS frequency,
        SUM(p.price_paid) AS monetary
    FROM users u
    JOIN purchases p ON u.user_id = p.user_id
    GROUP BY u.user_id, u.username, u.email
),
rfm_scored AS (
    SELECT
        user_id,
        username,
        email,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM rfm_raw
)
SELECT
    username,
    email,
    recency_days,
    frequency,
    ROUND(monetary, 2) AS total_spent,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4
            THEN 'VIP — Offer exclusive early access to new launches'
        WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3
            THEN 'Loyal — Send loyalty rewards and personalised recommendations'
        WHEN r_score >= 4 AND f_score <= 2
            THEN 'New — Nurture with welcome series and first-purchase discount'
        WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3
            THEN 'At Risk — Send win-back campaign with limited time offer'
        WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4
            THEN 'Cannot Lose — Personal outreach from account manager'
        WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2
            THEN 'Lost — Low priority, sunset or last chance email only'
        ELSE 'Developing — Monitor and nurture with regular content'
    END AS recommended_action
FROM rfm_scored
ORDER BY monetary DESC;