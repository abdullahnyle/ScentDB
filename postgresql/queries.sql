-- ScentDB: Analytical Queries

-- 1. Top rated fragrances (average score)
SELECT 
    f.name AS fragrance,
    b.name AS brand,
    ROUND(AVG(r.score), 2) AS avg_rating,
    COUNT(r.rating_id) AS total_reviews
FROM fragrances f
JOIN brands b ON f.brand_id = b.brand_id
JOIN ratings r ON f.fragrance_id = r.fragrance_id
GROUP BY f.name, b.name
ORDER BY avg_rating DESC;

-- 2. Most purchased fragrances
SELECT 
    f.name AS fragrance,
    b.name AS brand,
    COUNT(p.purchase_id) AS total_purchases,
    SUM(p.price_paid) AS total_revenue
FROM fragrances f
JOIN brands b ON f.brand_id = b.brand_id
JOIN purchases p ON f.fragrance_id = p.fragrance_id
GROUP BY f.name, b.name
ORDER BY total_purchases DESC;

-- 3. User purchase history with ratings
SELECT 
    u.username,
    f.name AS fragrance,
    p.purchase_date,
    p.price_paid,
    r.score AS rating
FROM users u
JOIN purchases p ON u.user_id = p.user_id
JOIN fragrances f ON p.fragrance_id = f.fragrance_id
LEFT JOIN ratings r ON u.user_id = r.user_id 
    AND f.fragrance_id = r.fragrance_id
ORDER BY u.username, p.purchase_date;

-- 4. Brand performance summary
SELECT 
    b.name AS brand,
    COUNT(DISTINCT f.fragrance_id) AS total_fragrances,
    ROUND(AVG(r.score), 2) AS avg_rating,
    SUM(p.price_paid) AS total_revenue
FROM brands b
JOIN fragrances f ON b.brand_id = f.brand_id
LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
GROUP BY b.name
ORDER BY total_revenue DESC;

-- 5. Users who purchased but never rated (follow up targets)
SELECT 
    u.username,
    u.email,
    COUNT(p.purchase_id) AS purchases_made
FROM users u
JOIN purchases p ON u.user_id = p.user_id
WHERE u.user_id NOT IN (
    SELECT DISTINCT user_id FROM ratings
)
GROUP BY u.username, u.email;

-- 6. Window function: Rank fragrances by revenue per brand
SELECT 
    b.name AS brand,
    f.name AS fragrance,
    SUM(p.price_paid) AS revenue,
    RANK() OVER (PARTITION BY b.name ORDER BY SUM(p.price_paid) DESC) AS rank_in_brand
FROM brands b
JOIN fragrances f ON b.brand_id = f.brand_id
JOIN purchases p ON f.fragrance_id = p.fragrance_id
GROUP BY b.name, f.name
ORDER BY brand, rank_in_brand;