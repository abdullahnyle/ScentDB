-- ScentDB: Advanced Functions & Stored Procedures
-- =====================
-- These functions encapsulate the kind of business logic that
-- gets written once and called everywhere. A junior analyst
-- writes the same revenue calculation in five different queries.
-- A senior one puts it in a function and calls it consistently.
-- That's the difference these demonstrate.
-- =====================

-- =====================
-- USER LIFETIME VALUE (LTV)
-- =====================
-- LTV is one of the most important metrics in any retail business.
-- It answers: how much is this customer actually worth to us?
-- Not just today's purchase — the total value they'll generate
-- over their entire relationship with the platform.

CREATE OR REPLACE FUNCTION calculate_user_ltv(p_user_id INT)
RETURNS TABLE (
    username VARCHAR,
    total_spent DECIMAL,
    avg_order_value DECIMAL,
    purchase_frequency DECIMAL,
    days_as_customer INT,
    projected_annual_value DECIMAL,
    ltv_segment VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    WITH user_stats AS (
        SELECT
            u.username,
            COUNT(p.purchase_id) AS purchase_count,
            SUM(p.price_paid) AS total_spent,
            AVG(p.price_paid) AS avg_order,
            MIN(p.purchase_date) AS first_purchase,
            MAX(p.purchase_date) AS last_purchase,
            MAX(p.purchase_date) - MIN(p.purchase_date) AS customer_lifespan
        FROM users u
        JOIN purchases p ON u.user_id = p.user_id
        WHERE u.user_id = p_user_id
        GROUP BY u.username
    )
    SELECT
        us.username::VARCHAR,
        us.total_spent,
        ROUND(us.avg_order, 2),
        -- Purchase frequency: purchases per month
        ROUND(
            us.purchase_count::DECIMAL /
            GREATEST(EXTRACT(DAY FROM us.customer_lifespan) / 30.0, 1),
            2
        ) AS purchase_frequency,
        EXTRACT(DAY FROM us.customer_lifespan)::INT AS days_as_customer,
        -- Project annual value based on current behavior
        ROUND(
            us.avg_order *
            (us.purchase_count::DECIMAL /
            GREATEST(EXTRACT(DAY FROM us.customer_lifespan) / 30.0, 1)) * 12,
            2
        ) AS projected_annual_value,
        -- Segment them for marketing purposes
        CASE
            WHEN us.total_spent > 500 THEN 'Platinum'
            WHEN us.total_spent > 250 THEN 'Gold'
            WHEN us.total_spent > 100 THEN 'Silver'
            ELSE 'Bronze'
        END::VARCHAR AS ltv_segment
    FROM user_stats us;
END;
$$ LANGUAGE plpgsql;

-- Run it for all users
SELECT * FROM calculate_user_ltv(1);
SELECT * FROM calculate_user_ltv(2);
SELECT * FROM calculate_user_ltv(3);

-- =====================
-- FRAGRANCE SCORING ALGORITHM
-- =====================
-- A composite score that combines ratings, purchase volume,
-- wishlist demand, and price positioning into a single number.
-- This is the kind of thing a product team uses to decide
-- which fragrances to feature, restock, or discontinue.

CREATE OR REPLACE FUNCTION calculate_fragrance_score(p_fragrance_id INT)
RETURNS TABLE (
    fragrance_name VARCHAR,
    brand_name VARCHAR,
    avg_rating DECIMAL,
    purchase_volume INT,
    wishlist_demand INT,
    review_sentiment_avg DECIMAL,
    composite_score DECIMAL,
    recommendation VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    WITH fragrance_stats AS (
        SELECT
            f.name AS fname,
            b.name AS bname,
            COALESCE(AVG(r.score), 0) AS avg_r,
            COUNT(DISTINCT p.purchase_id) AS purchases,
            COUNT(DISTINCT w.wishlist_id) AS wishlists,
            COUNT(DISTINCT r.rating_id) AS review_count
        FROM fragrances f
        JOIN brands b ON f.brand_id = b.brand_id
        LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
        LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
        LEFT JOIN wishlists w ON f.fragrance_id = w.fragrance_id
        WHERE f.fragrance_id = p_fragrance_id
        GROUP BY f.name, b.name
    )
    SELECT
        fs.fname::VARCHAR,
        fs.bname::VARCHAR,
        ROUND(fs.avg_r, 2),
        fs.purchases::INT,
        fs.wishlists::INT,
        ROUND(fs.avg_r, 2) AS sentiment,
        -- Composite score: weighted combination of all signals
        ROUND(
            (fs.avg_r * 0.40) +
            (fs.purchases * 0.30) +
            (fs.wishlists * 0.20) +
            (fs.review_count * 0.10),
            3
        ) AS composite_score,
        CASE
            WHEN (fs.avg_r * 0.40) + (fs.purchases * 0.30) +
                 (fs.wishlists * 0.20) + (fs.review_count * 0.10) >= 7
                THEN 'Feature prominently'
            WHEN (fs.avg_r * 0.40) + (fs.purchases * 0.30) +
                 (fs.wishlists * 0.20) + (fs.review_count * 0.10) >= 4
                THEN 'Maintain current positioning'
            WHEN fs.purchases = 0 AND fs.wishlists = 0
                THEN 'Consider discontinuing'
            ELSE 'Monitor closely'
        END::VARCHAR AS recommendation
    FROM fragrance_stats fs;
END;
$$ LANGUAGE plpgsql;

-- Score every fragrance in the catalog
SELECT * FROM calculate_fragrance_score(1);
SELECT * FROM calculate_fragrance_score(2);
SELECT * FROM calculate_fragrance_score(3);
SELECT * FROM calculate_fragrance_score(4);
SELECT * FROM calculate_fragrance_score(5);

-- =====================
-- INVENTORY DEMAND FORECASTING
-- =====================
-- Uses purchase velocity to predict how many units will be
-- needed in the next 30, 60, and 90 days.
-- Simple linear forecasting — not ML, just honest math.

CREATE OR REPLACE FUNCTION forecast_demand(p_fragrance_id INT, p_days_ahead INT)
RETURNS TABLE (
    fragrance_name VARCHAR,
    historical_purchases INT,
    avg_purchases_per_month DECIMAL,
    forecast_period_days INT,
    predicted_units DECIMAL,
    confidence VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    WITH purchase_history AS (
        SELECT
            f.name,
            COUNT(p.purchase_id) AS total_purchases,
            MIN(p.purchase_date) AS first_sale,
            MAX(p.purchase_date) AS last_sale,
            MAX(p.purchase_date) - MIN(p.purchase_date) AS sales_window
        FROM fragrances f
        LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
        WHERE f.fragrance_id = p_fragrance_id
        GROUP BY f.name
    )
    SELECT
        ph.name::VARCHAR,
        ph.total_purchases::INT,
        -- Monthly purchase rate
        ROUND(
            ph.total_purchases::DECIMAL /
            GREATEST(EXTRACT(DAY FROM ph.sales_window) / 30.0, 1),
            2
        ) AS monthly_rate,
        p_days_ahead,
        -- Scale monthly rate to the forecast period
        ROUND(
            (ph.total_purchases::DECIMAL /
            GREATEST(EXTRACT(DAY FROM ph.sales_window) / 30.0, 1)) *
            (p_days_ahead / 30.0),
            1
        ) AS predicted_units,
        -- Confidence based on how much data we have
        CASE
            WHEN ph.total_purchases >= 10 THEN 'High'
            WHEN ph.total_purchases >= 5  THEN 'Medium'
            WHEN ph.total_purchases >= 2  THEN 'Low'
            ELSE 'Insufficient data'
        END::VARCHAR AS confidence
    FROM purchase_history ph;
END;
$$ LANGUAGE plpgsql;

-- Forecast demand for the next 30, 60, and 90 days
SELECT * FROM forecast_demand(1, 30);
SELECT * FROM forecast_demand(1, 60);
SELECT * FROM forecast_demand(1, 90);
SELECT * FROM forecast_demand(2, 30);

-- =====================
-- PRICE ELASTICITY ESTIMATOR
-- =====================
-- Does a higher price hurt sales volume for a fragrance?
-- This function compares average rating scores against price
-- to estimate whether customers feel the price is justified.
-- Real elasticity needs time-series price changes to measure properly
-- but this proxy gives a useful directional signal.

CREATE OR REPLACE FUNCTION estimate_price_sensitivity(p_brand_id INT)
RETURNS TABLE (
    fragrance_name VARCHAR,
    price_usd DECIMAL,
    avg_rating DECIMAL,
    purchase_count INT,
    price_per_rating_point DECIMAL,
    value_verdict VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.name::VARCHAR,
        f.price_usd,
        ROUND(COALESCE(AVG(r.score), 0), 2) AS avg_rating,
        COUNT(DISTINCT p.purchase_id)::INT AS purchase_count,
        -- How much does each rating point cost?
        -- Lower = better value perception
        ROUND(
            f.price_usd / NULLIF(AVG(r.score), 0),
            2
        ) AS price_per_rating_point,
        CASE
            WHEN f.price_usd / NULLIF(AVG(r.score), 0) < 15
                THEN 'Exceptional value'
            WHEN f.price_usd / NULLIF(AVG(r.score), 0) < 25
                THEN 'Good value'
            WHEN f.price_usd / NULLIF(AVG(r.score), 0) < 40
                THEN 'Fair value'
            ELSE 'Premium priced'
        END::VARCHAR AS value_verdict
    FROM fragrances f
    LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
    LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
    WHERE f.brand_id = p_brand_id
    GROUP BY f.name, f.price_usd
    ORDER BY price_per_rating_point ASC;
END;
$$ LANGUAGE plpgsql;

-- Run for each brand
SELECT * FROM estimate_price_sensitivity(1); -- Creed
SELECT * FROM estimate_price_sensitivity(2); -- Dior
SELECT * FROM estimate_price_sensitivity(3); -- Tom Ford

-- =====================
-- ADDITIONAL TRIGGERS
-- =====================

-- Trigger: Automatically remove from wishlist when purchased
CREATE OR REPLACE FUNCTION auto_remove_from_wishlist()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM wishlists
    WHERE user_id = NEW.user_id
    AND fragrance_id = NEW.fragrance_id;

    IF FOUND THEN
        INSERT INTO audit_log (table_name, action, performed_by, details)
        VALUES (
            'wishlists',
            'AUTO_DELETE',
            NEW.user_id,
            CONCAT('Auto-removed fragrance ', NEW.fragrance_id,
                   ' from wishlist after purchase')
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER after_purchase_clean_wishlist
AFTER INSERT ON purchases
FOR EACH ROW
EXECUTE FUNCTION auto_remove_from_wishlist();

-- Trigger: Flag suspicious purchase patterns
-- More than 3 purchases of the same fragrance by the same user
-- could indicate reselling or a data entry error
CREATE OR REPLACE FUNCTION flag_suspicious_purchase()
RETURNS TRIGGER AS $$
DECLARE
    purchase_count INT;
BEGIN
    SELECT COUNT(*) INTO purchase_count
    FROM purchases
    WHERE user_id = NEW.user_id
    AND fragrance_id = NEW.fragrance_id;

    IF purchase_count > 3 THEN
        INSERT INTO audit_log (table_name, action, performed_by, details)
        VALUES (
            'purchases',
            'SUSPICIOUS_PATTERN',
            NEW.user_id,
            CONCAT('User ', NEW.user_id, ' has now purchased fragrance ',
                   NEW.fragrance_id, ' ', purchase_count + 1, ' times. Review recommended.')
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_suspicious_purchases
AFTER INSERT ON purchases
FOR EACH ROW
EXECUTE FUNCTION flag_suspicious_purchase();

-- Trigger: Keep a rating history log when scores are updated
-- So we can track if a user changes their mind about a fragrance
CREATE TABLE IF NOT EXISTS rating_history (
    history_id SERIAL PRIMARY KEY,
    rating_id INT,
    user_id INT,
    fragrance_id INT,
    old_score INT,
    new_score INT,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    change_reason TEXT
);

CREATE OR REPLACE FUNCTION log_rating_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.score != NEW.score THEN
        INSERT INTO rating_history (
            rating_id, user_id, fragrance_id,
            old_score, new_score, change_reason
        )
        VALUES (
            OLD.rating_id,
            OLD.user_id,
            OLD.fragrance_id,
            OLD.score,
            NEW.score,
            CONCAT('Score changed from ', OLD.score, ' to ', NEW.score)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER track_rating_changes
AFTER UPDATE ON ratings
FOR EACH ROW
EXECUTE FUNCTION log_rating_change();