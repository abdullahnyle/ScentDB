-- ScentDB: Data Quality Framework
-- =====================
-- Bad data is worse than no data. No data tells you nothing.
-- Bad data tells you something wrong and you act on it.
-- A business that makes pricing decisions on corrupted purchase
-- records, or sends win-back campaigns to users who never
-- actually churned because their last purchase date was
-- recorded incorrectly, is not just wasting money.
-- It is making things actively worse with confidence.
--
-- Data quality work is unglamorous. Nobody puts it in a
-- pitch deck. But every senior analyst and every data
-- engineer knows it is the foundation everything else
-- sits on. A portfolio that includes a proper data quality
-- framework signals something most junior candidates miss:
-- that you understand data as a system with failure modes,
-- not just a collection of tables to query.
--
-- This file builds a full data quality framework for ScentDB.
-- It covers completeness, consistency, validity, uniqueness,
-- referential integrity, and freshness — the six dimensions
-- that define whether a dataset can be trusted.
-- =====================

-- =====================
-- DIMENSION 1: COMPLETENESS
-- =====================
-- Are the fields that should have values actually populated?
-- NULL values in critical columns are silent killers —
-- they do not throw errors, they just quietly skew every
-- aggregate that touches them.

-- Check for NULL values across all critical columns
SELECT
    'users' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE username IS NULL)     AS null_username,
    COUNT(*) FILTER (WHERE email IS NULL)         AS null_email,
    COUNT(*) FILTER (WHERE age IS NULL)           AS null_age,
    COUNT(*) FILTER (WHERE country IS NULL)       AS null_country,
    COUNT(*) FILTER (WHERE joined_date IS NULL)   AS null_joined_date,
    -- Overall completeness score
    ROUND(
        (1 - (
            COUNT(*) FILTER (WHERE username IS NULL OR
                                   email IS NULL OR
                                   country IS NULL)::DECIMAL /
            NULLIF(COUNT(*) * 3, 0)
        )) * 100,
        1
    ) AS completeness_score_percent
FROM users

UNION ALL

SELECT
    'fragrances',
    COUNT(*),
    COUNT(*) FILTER (WHERE name IS NULL),
    COUNT(*) FILTER (WHERE brand_id IS NULL),
    COUNT(*) FILTER (WHERE concentration IS NULL),
    COUNT(*) FILTER (WHERE price_usd IS NULL),
    COUNT(*) FILTER (WHERE gender_target IS NULL),
    ROUND(
        (1 - (
            COUNT(*) FILTER (WHERE name IS NULL OR
                                   brand_id IS NULL OR
                                   price_usd IS NULL)::DECIMAL /
            NULLIF(COUNT(*) * 3, 0)
        )) * 100,
        1
    )
FROM fragrances

UNION ALL

SELECT
    'purchases',
    COUNT(*),
    COUNT(*) FILTER (WHERE user_id IS NULL),
    COUNT(*) FILTER (WHERE fragrance_id IS NULL),
    COUNT(*) FILTER (WHERE price_paid IS NULL),
    COUNT(*) FILTER (WHERE purchase_date IS NULL),
    COUNT(*) FILTER (WHERE bottle_size_ml IS NULL),
    ROUND(
        (1 - (
            COUNT(*) FILTER (WHERE user_id IS NULL OR
                                   fragrance_id IS NULL OR
                                   price_paid IS NULL)::DECIMAL /
            NULLIF(COUNT(*) * 3, 0)
        )) * 100,
        1
    )
FROM purchases

UNION ALL

SELECT
    'ratings',
    COUNT(*),
    COUNT(*) FILTER (WHERE user_id IS NULL),
    COUNT(*) FILTER (WHERE fragrance_id IS NULL),
    COUNT(*) FILTER (WHERE score IS NULL),
    COUNT(*) FILTER (WHERE review_text IS NULL),
    COUNT(*) FILTER (WHERE rated_at IS NULL),
    ROUND(
        (1 - (
            COUNT(*) FILTER (WHERE user_id IS NULL OR
                                   fragrance_id IS NULL OR
                                   score IS NULL)::DECIMAL /
            NULLIF(COUNT(*) * 3, 0)
        )) * 100,
        1
    )
FROM ratings;

-- =====================
-- DIMENSION 2: VALIDITY
-- =====================
-- Are the values that exist actually valid?
-- A score of 11 is not NULL — it just violates the rules.
-- An email without an @ symbol is not NULL either.
-- Validity checks catch the bad data that completeness misses.

-- Check for out of range values
SELECT
    'ratings.score out of range (1-10)' AS check_name,
    COUNT(*) AS violations
FROM ratings
WHERE score < 1 OR score > 10

UNION ALL

SELECT
    'purchases.price_paid negative or zero',
    COUNT(*)
FROM purchases
WHERE price_paid <= 0

UNION ALL

SELECT
    'purchases.bottle_size_ml unrealistic (>1000ml or <=0)',
    COUNT(*)
FROM purchases
WHERE bottle_size_ml > 1000 OR bottle_size_ml <= 0

UNION ALL

SELECT
    'users.age unrealistic (under 13 or over 100)',
    COUNT(*)
FROM users
WHERE age < 13 OR age > 100

UNION ALL

SELECT
    'fragrances.price_usd negative or zero',
    COUNT(*)
FROM fragrances
WHERE price_usd <= 0

UNION ALL

SELECT
    'fragrances.release_year unrealistic (before 1900 or future)',
    COUNT(*)
FROM fragrances
WHERE release_year < 1900
   OR release_year > EXTRACT(YEAR FROM CURRENT_DATE)

UNION ALL

SELECT
    'purchases.purchase_date in the future',
    COUNT(*)
FROM purchases
WHERE purchase_date > CURRENT_DATE

UNION ALL

SELECT
    'ratings.rated_at before purchase_date for same user/fragrance',
    COUNT(*)
FROM ratings r
JOIN purchases p ON r.user_id = p.user_id
    AND r.fragrance_id = p.fragrance_id
WHERE r.rated_at::DATE < p.purchase_date;

-- Check email format validity
SELECT
    'users.email missing @ symbol' AS check_name,
    COUNT(*) AS violations,
    ARRAY_AGG(email) AS offending_values
FROM users
WHERE email NOT LIKE '%@%'

UNION ALL

SELECT
    'users.email missing domain extension',
    COUNT(*),
    ARRAY_AGG(email)
FROM users
WHERE email NOT LIKE '%.%';

-- =====================
-- DIMENSION 3: UNIQUENESS
-- =====================
-- Duplicate records are one of the most common and most
-- damaging data quality problems. A user counted twice
-- inflates your customer metrics. A purchase recorded
-- twice inflates revenue. Neither shows up as an error —
-- the database happily returns wrong answers.

-- Duplicate users by email
SELECT
    'duplicate user emails' AS check_name,
    COUNT(*) AS duplicate_count,
    ARRAY_AGG(email) AS duplicate_emails
FROM (
    SELECT email, COUNT(*) AS occurrences
    FROM users
    GROUP BY email
    HAVING COUNT(*) > 1
) dupes;

-- Duplicate ratings: same user rating same fragrance twice
SELECT
    'duplicate ratings (same user, same fragrance)' AS check_name,
    COUNT(*) AS duplicate_count
FROM (
    SELECT user_id, fragrance_id, COUNT(*) AS occurrences
    FROM ratings
    GROUP BY user_id, fragrance_id
    HAVING COUNT(*) > 1
) dupes;

-- Suspicious duplicate purchases on the same day
SELECT
    u.username,
    f.name AS fragrance,
    p.purchase_date,
    COUNT(*) AS same_day_purchases,
    SUM(p.price_paid) AS total_charged,
    'Possible duplicate charge — review manually' AS flag
FROM purchases p
JOIN users u ON p.user_id = u.user_id
JOIN fragrances f ON p.fragrance_id = f.fragrance_id
GROUP BY u.username, f.name, p.purchase_date
HAVING COUNT(*) > 1
ORDER BY same_day_purchases DESC;

-- =====================
-- DIMENSION 4: CONSISTENCY
-- =====================
-- Are related fields telling the same story?
-- Price paid should align with the listed price.
-- A rating should not exist for a fragrance the user never bought.
-- Inconsistencies like these reveal process failures upstream.

-- Price paid vs listed price — large discrepancies
SELECT
    u.username,
    f.name AS fragrance,
    f.price_usd AS listed_price,
    p.price_paid AS charged_price,
    ROUND(ABS(p.price_paid - f.price_usd), 2) AS price_discrepancy,
    ROUND(ABS(p.price_paid - f.price_usd) / f.price_usd * 100, 1)
        AS discrepancy_percent,
    CASE
        WHEN ABS(p.price_paid - f.price_usd) / f.price_usd > 0.30
            THEN 'Major discrepancy — investigate immediately'
        WHEN ABS(p.price_paid - f.price_usd) / f.price_usd > 0.10
            THEN 'Minor discrepancy — likely discount applied'
        ELSE 'Within acceptable range'
    END AS assessment
FROM purchases p
JOIN fragrances f ON p.fragrance_id = f.fragrance_id
JOIN users u ON p.user_id = u.user_id
WHERE ABS(p.price_paid - f.price_usd) > 5
ORDER BY discrepancy_percent DESC;

-- Ratings without corresponding purchases
-- A user should not be able to rate something they never bought
SELECT
    u.username,
    f.name AS fragrance,
    r.score,
    r.rated_at,
    'Rating exists but no purchase record found' AS data_issue
FROM ratings r
JOIN users u ON r.user_id = u.user_id
JOIN fragrances f ON r.fragrance_id = f.fragrance_id
WHERE NOT EXISTS (
    SELECT 1 FROM purchases p
    WHERE p.user_id = r.user_id
    AND p.fragrance_id = r.fragrance_id
);

-- Wishlist items already purchased
-- These should be auto-cleaned by the trigger we built
-- If any exist it means the trigger failed somewhere
SELECT
    u.username,
    f.name AS fragrance,
    w.added_at AS wishlisted_on,
    p.purchase_date AS purchased_on,
    'Wishlist item not cleaned after purchase — trigger may have failed' AS flag
FROM wishlists w
JOIN purchases p ON w.user_id = p.user_id
    AND w.fragrance_id = p.fragrance_id
JOIN users u ON w.user_id = u.user_id
JOIN fragrances f ON w.fragrance_id = f.fragrance_id
WHERE p.purchase_date >= w.added_at::DATE;

-- =====================
-- DIMENSION 5: REFERENTIAL INTEGRITY
-- =====================
-- Foreign key constraints prevent most referential integrity
-- violations at insert time. But constraints can be disabled,
-- bulk loads can bypass them, and legacy migrations often
-- create orphaned records. These checks verify the constraints
-- are actually holding.

SELECT
    'purchases with no matching user' AS check_name,
    COUNT(*) AS violations
FROM purchases p
WHERE NOT EXISTS (
    SELECT 1 FROM users u WHERE u.user_id = p.user_id
)

UNION ALL

SELECT
    'purchases with no matching fragrance',
    COUNT(*)
FROM purchases p
WHERE NOT EXISTS (
    SELECT 1 FROM fragrances f WHERE f.fragrance_id = p.fragrance_id
)

UNION ALL

SELECT
    'ratings with no matching user',
    COUNT(*)
FROM ratings r
WHERE NOT EXISTS (
    SELECT 1 FROM users u WHERE u.user_id = r.user_id
)

UNION ALL

SELECT
    'ratings with no matching fragrance',
    COUNT(*)
FROM ratings r
WHERE NOT EXISTS (
    SELECT 1 FROM fragrances f WHERE f.fragrance_id = r.fragrance_id
)

UNION ALL

SELECT
    'fragrances with no matching brand',
    COUNT(*)
FROM fragrances f
WHERE NOT EXISTS (
    SELECT 1 FROM brands b WHERE b.brand_id = f.brand_id
)

UNION ALL

SELECT
    'fragrance_note_map with no matching note',
    COUNT(*)
FROM fragrance_note_map fnm
WHERE NOT EXISTS (
    SELECT 1 FROM notes n WHERE n.note_id = fnm.note_id
);

-- =====================
-- DIMENSION 6: FRESHNESS
-- =====================
-- How recently was the data updated?
-- Stale data is a specific kind of quality problem.
-- A recommendation engine running on six-month-old
-- purchase data is not wrong exactly — it just does not
-- reflect who the customer is anymore.

SELECT
    'purchases' AS table_name,
    MAX(purchase_date) AS most_recent_record,
    MIN(purchase_date) AS oldest_record,
    EXTRACT(DAY FROM (CURRENT_DATE - MAX(purchase_date)))::INT
        AS days_since_last_update,
    COUNT(*) AS total_records,
    CASE
        WHEN EXTRACT(DAY FROM (CURRENT_DATE - MAX(purchase_date))) <= 7
            THEN 'Fresh — updated within the last week'
        WHEN EXTRACT(DAY FROM (CURRENT_DATE - MAX(purchase_date))) <= 30
            THEN 'Acceptable — updated within the last month'
        WHEN EXTRACT(DAY FROM (CURRENT_DATE - MAX(purchase_date))) <= 90
            THEN 'Stale — last update was over a month ago'
        ELSE 'Very stale — data may no longer reflect reality'
    END AS freshness_status
FROM purchases

UNION ALL

SELECT
    'ratings',
    MAX(rated_at::DATE),
    MIN(rated_at::DATE),
    EXTRACT(DAY FROM (CURRENT_DATE - MAX(rated_at::DATE)))::INT,
    COUNT(*),
    CASE
        WHEN EXTRACT(DAY FROM (CURRENT_DATE - MAX(rated_at::DATE))) <= 7
            THEN 'Fresh'
        WHEN EXTRACT(DAY FROM (CURRENT_DATE - MAX(rated_at::DATE))) <= 30
            THEN 'Acceptable'
        ELSE 'Stale'
    END
FROM ratings;

-- =====================
-- MASTER DATA QUALITY SCORECARD
-- =====================
-- Pull all six dimensions into a single executive summary.
-- This is what you show in a data governance meeting —
-- one number per dimension, one overall health score,
-- and a clear flag for anything that needs immediate attention.

WITH completeness_score AS (
    SELECT
        ROUND(
            (SELECT COUNT(*) FROM users WHERE email IS NOT NULL
             AND username IS NOT NULL)::DECIMAL /
            NULLIF((SELECT COUNT(*) FROM users), 0) * 100,
            1
        ) AS score
),
validity_score AS (
    SELECT
        ROUND(
            (1 - (
                SELECT COUNT(*) FROM ratings
                WHERE score < 1 OR score > 10
            )::DECIMAL / NULLIF((SELECT COUNT(*) FROM ratings), 0)
            ) * 100,
            1
        ) AS score
),
uniqueness_score AS (
    SELECT
        ROUND(
            (1 - (
                SELECT COUNT(*) FROM (
                    SELECT email FROM users
                    GROUP BY email HAVING COUNT(*) > 1
                ) dupes
            )::DECIMAL / NULLIF((SELECT COUNT(*) FROM users), 0)
            ) * 100,
            1
        ) AS score
),
integrity_score AS (
    SELECT
        ROUND(
            (1 - (
                SELECT COUNT(*) FROM purchases p
                WHERE NOT EXISTS (
                    SELECT 1 FROM users u WHERE u.user_id = p.user_id
                )
            )::DECIMAL / NULLIF((SELECT COUNT(*) FROM purchases), 0)
            ) * 100,
            1
        ) AS score
)
SELECT
    'Completeness' AS dimension,
    cs.score AS score_percent,
    CASE WHEN cs.score >= 95 THEN 'Pass' ELSE 'Fail' END AS status
FROM completeness_score cs

UNION ALL

SELECT 'Validity', vs.score,
    CASE WHEN vs.score >= 98 THEN 'Pass' ELSE 'Fail' END
FROM validity_score vs

UNION ALL

SELECT 'Uniqueness', us.score,
    CASE WHEN us.score >= 99 THEN 'Pass' ELSE 'Fail' END
FROM uniqueness_score us

UNION ALL

SELECT 'Referential Integrity', is2.score,
    CASE WHEN is2.score >= 100 THEN 'Pass' ELSE 'Fail' END
FROM integrity_score is2

ORDER BY score_percent ASC;