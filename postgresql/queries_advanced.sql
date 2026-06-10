-- ScentDB: Advanced Queries

-- =====================
-- USING THE VIEWS
-- =====================

-- What does each fragrance look like at a glance?
SELECT * FROM fragrance_profile
ORDER BY avg_rating DESC;

-- How active is each user on the platform?
SELECT * FROM user_activity_summary
ORDER BY total_spent DESC;

-- Which fragrance notes show up the most across the catalog?
SELECT * FROM note_popularity;

-- =====================
-- USING THE STORED PROCEDURE
-- =====================

-- Get personalized recommendations for user 1
-- (based on notes from their highest rated fragrances)
SELECT * FROM get_recommendations(1);

-- =====================
-- USING THE TRIGGER
-- =====================

-- Insert a new purchase and watch the trigger fire automatically
INSERT INTO purchases (user_id, fragrance_id, purchase_date, price_paid, bottle_size_ml)
VALUES (3, 6, '2024-06-15', 140.00, 100);

-- Check the audit log — the trigger should have logged it
SELECT * FROM audit_log;

-- =====================
-- DEEPER ANALYTICAL QUERIES
-- =====================

-- Which note family dominates the best rated fragrances?
SELECT
    n.family,
    ROUND(AVG(r.score), 2) AS avg_rating,
    COUNT(DISTINCT f.fragrance_id) AS fragrances_using_it
FROM notes n
JOIN fragrance_note_map fnm ON n.note_id = fnm.note_id
JOIN fragrances f ON fnm.fragrance_id = f.fragrance_id
JOIN ratings r ON f.fragrance_id = r.fragrance_id
GROUP BY n.family
ORDER BY avg_rating DESC;

-- Which users have the most expensive taste?
-- (average price of fragrances they actually bought)
SELECT
    u.username,
    u.country,
    ROUND(AVG(f.price_usd), 2) AS avg_fragrance_price,
    COUNT(p.purchase_id) AS total_purchases
FROM users u
JOIN purchases p ON u.user_id = p.user_id
JOIN fragrances f ON p.fragrance_id = f.fragrance_id
GROUP BY u.username, u.country
ORDER BY avg_fragrance_price DESC;

-- Do users who spend more also rate higher?
-- Correlation between spending and rating generosity
SELECT
    u.username,
    SUM(p.price_paid) AS total_spent,
    ROUND(AVG(r.score), 2) AS avg_rating_given
FROM users u
JOIN purchases p ON u.user_id = p.user_id
JOIN ratings r ON u.user_id = r.user_id
GROUP BY u.username
ORDER BY total_spent DESC;

-- What sits on wishlists that users haven't bought yet?
-- Good signal for demand forecasting
SELECT
    u.username,
    f.name AS wishlist_fragrance,
    b.name AS brand,
    f.price_usd,
    w.priority
FROM wishlists w
JOIN users u ON w.user_id = u.user_id
JOIN fragrances f ON w.fragrance_id = f.fragrance_id
JOIN brands b ON f.brand_id = b.brand_id
WHERE w.fragrance_id NOT IN (
    SELECT fragrance_id FROM purchases
    WHERE user_id = w.user_id
)
ORDER BY u.username, w.priority;

-- Monthly purchase trends
SELECT
    TO_CHAR(purchase_date, 'YYYY-MM') AS month,
    COUNT(purchase_id) AS total_purchases,
    SUM(price_paid) AS monthly_revenue,
    ROUND(AVG(price_paid), 2) AS avg_order_value
FROM purchases
GROUP BY TO_CHAR(purchase_date, 'YYYY-MM')
ORDER BY month;

-- Running total revenue over time per user
SELECT
    u.username,
    p.purchase_date,
    p.price_paid,
    SUM(p.price_paid) OVER (
        PARTITION BY u.user_id
        ORDER BY p.purchase_date
    ) AS running_total_spent
FROM users u
JOIN purchases p ON u.user_id = p.user_id
ORDER BY u.username, p.purchase_date;