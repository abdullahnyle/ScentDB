-- ScentDB: Advanced PostgreSQL Schema
-- Fragrance Notes, Stored Procedures, Triggers, Views

-- =====================
-- FRAGRANCE NOTES TABLES
-- =====================

-- Notes Master Table (Bergamot, Oud, Sandalwood etc.)
CREATE TABLE notes (
    note_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50), -- Top, Middle, Base
    family VARCHAR(50)    -- Citrus, Woody, Floral, Oriental etc.
);

-- Maps which notes belong to which fragrance
CREATE TABLE fragrance_note_map (
    map_id SERIAL PRIMARY KEY,
    fragrance_id INT REFERENCES fragrances(fragrance_id),
    note_id INT REFERENCES notes(note_id),
    note_type VARCHAR(20) -- Top, Middle, Base
);

-- =====================
-- WISHLIST TABLE
-- =====================
CREATE TABLE wishlists (
    wishlist_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id),
    fragrance_id INT REFERENCES fragrances(fragrance_id),
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    priority INT CHECK (priority BETWEEN 1 AND 5)
);

-- =====================
-- AUDIT LOG TABLE
-- =====================
CREATE TABLE audit_log (
    log_id SERIAL PRIMARY KEY,
    table_name VARCHAR(50),
    action VARCHAR(20),    -- INSERT, UPDATE, DELETE
    performed_by INT,      -- user_id
    performed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    details TEXT
);

-- =====================
-- SEED NOTES DATA
-- =====================
INSERT INTO notes (name, category, family) VALUES
('Bergamot', 'Top', 'Citrus'),
('Lemon', 'Top', 'Citrus'),
('Pink Pepper', 'Top', 'Spicy'),
('Rose', 'Middle', 'Floral'),
('Jasmine', 'Middle', 'Floral'),
('Lavender', 'Middle', 'Aromatic'),
('Oud', 'Base', 'Woody'),
('Sandalwood', 'Base', 'Woody'),
('Oakmoss', 'Base', 'Earthy'),
('Ambergris', 'Base', 'Animalic'),
('Vanilla', 'Base', 'Sweet'),
('Tobacco', 'Base', 'Smoky'),
('Patchouli', 'Base', 'Earthy'),
('Leather', 'Base', 'Animalic'),
('Vetiver', 'Base', 'Woody');

-- Map notes to fragrances
INSERT INTO fragrance_note_map (fragrance_id, note_id, note_type) VALUES
-- Aventus (id=1): Bergamot top, Oakmoss middle, Ambergris base
(1, 1, 'Top'),
(1, 9, 'Middle'),
(1, 10, 'Base'),
-- Sauvage (id=2): Bergamot top, Lavender middle, Ambergris base
(2, 1, 'Top'),
(2, 6, 'Middle'),
(2, 10, 'Base'),
-- Oud Wood (id=3): Pink Pepper top, Oud middle, Sandalwood base
(3, 3, 'Top'),
(3, 7, 'Middle'),
(3, 8, 'Base'),
-- Eros (id=4): Lemon top, Jasmine middle, Vanilla base
(4, 2, 'Top'),
(4, 5, 'Middle'),
(4, 11, 'Base'),
-- Bleu de Chanel (id=5): Bergamot top, Rose middle, Vetiver base
(5, 1, 'Top'),
(5, 4, 'Middle'),
(5, 15, 'Base');

-- Wishlist seed data
INSERT INTO wishlists (user_id, fragrance_id, priority) VALUES
(1, 3, 1),
(1, 5, 2),
(2, 1, 1),
(3, 7, 3),
(4, 5, 1),
(4, 1, 2);

-- =====================
-- VIEWS
-- =====================

-- View 1: Full fragrance profile with brand + avg rating
CREATE VIEW fragrance_profile AS
SELECT
    f.fragrance_id,
    f.name AS fragrance,
    b.name AS brand,
    f.concentration,
    f.gender_target,
    f.price_usd,
    ROUND(AVG(r.score), 2) AS avg_rating,
    COUNT(DISTINCT p.purchase_id) AS total_purchases
FROM fragrances f
JOIN brands b ON f.brand_id = b.brand_id
LEFT JOIN ratings r ON f.fragrance_id = r.fragrance_id
LEFT JOIN purchases p ON f.fragrance_id = p.fragrance_id
GROUP BY f.fragrance_id, f.name, b.name, f.concentration, f.gender_target, f.price_usd;

-- View 2: User activity summary
CREATE VIEW user_activity_summary AS
SELECT
    u.user_id,
    u.username,
    u.country,
    COUNT(DISTINCT p.purchase_id) AS total_purchases,
    COUNT(DISTINCT r.rating_id) AS total_ratings,
    COUNT(DISTINCT w.wishlist_id) AS wishlist_items,
    ROUND(AVG(r.score), 2) AS avg_rating_given,
    SUM(p.price_paid) AS total_spent
FROM users u
LEFT JOIN purchases p ON u.user_id = p.user_id
LEFT JOIN ratings r ON u.user_id = r.user_id
LEFT JOIN wishlists w ON u.user_id = w.user_id
GROUP BY u.user_id, u.username, u.country;

-- View 3: Note popularity across all fragrances
CREATE VIEW note_popularity AS
SELECT
    n.name AS note,
    n.category,
    n.family,
    COUNT(fnm.fragrance_id) AS used_in_fragrances
FROM notes n
JOIN fragrance_note_map fnm ON n.note_id = fnm.note_id
GROUP BY n.name, n.category, n.family
ORDER BY used_in_fragrances DESC;

-- =====================
-- STORED PROCEDURE
-- =====================

-- Procedure: Get full fragrance recommendation for a user
-- based on their highest rated fragrances' shared notes
CREATE OR REPLACE FUNCTION get_recommendations(p_user_id INT)
RETURNS TABLE (
    recommended_fragrance VARCHAR,
    brand VARCHAR,
    price DECIMAL,
    shared_notes BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.name AS recommended_fragrance,
        b.name AS brand,
        f.price_usd AS price,
        COUNT(fnm.note_id) AS shared_notes
    FROM fragrances f
    JOIN brands b ON f.brand_id = b.brand_id
    JOIN fragrance_note_map fnm ON f.fragrance_id = fnm.fragrance_id
    WHERE fnm.note_id IN (
        -- Get notes from fragrances this user rated 8+
        SELECT DISTINCT fnm2.note_id
        FROM ratings r
        JOIN fragrance_note_map fnm2 ON r.fragrance_id = fnm2.fragrance_id
        WHERE r.user_id = p_user_id AND r.score >= 8
    )
    -- Exclude fragrances user already rated
    AND f.fragrance_id NOT IN (
        SELECT fragrance_id FROM ratings WHERE user_id = p_user_id
    )
    GROUP BY f.name, b.name, f.price_usd
    ORDER BY shared_notes DESC;
END;
$$ LANGUAGE plpgsql;

-- Usage: SELECT * FROM get_recommendations(1);

-- =====================
-- TRIGGER
-- =====================

-- Trigger: Auto log every new purchase into audit_log
CREATE OR REPLACE FUNCTION log_purchase()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (table_name, action, performed_by, details)
    VALUES (
        'purchases',
        'INSERT',
        NEW.user_id,
        CONCAT('User ', NEW.user_id, ' purchased fragrance ', NEW.fragrance_id, ' for $', NEW.price_paid)
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER after_purchase_insert
AFTER INSERT ON purchases
FOR EACH ROW
EXECUTE FUNCTION log_purchase();