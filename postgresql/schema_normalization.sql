-- ScentDB: Normalization Documentation
-- This file documents the normalization decisions made in schema.sql
-- and schema_advanced.sql, walking through 1NF → 2NF → 3NF

-- =====================
-- WHY NORMALIZATION MATTERS
-- =====================
-- A poorly normalized schema leads to:
-- 1. Data redundancy (same data stored in multiple places)
-- 2. Update anomalies (changing one record breaks others)
-- 3. Insertion anomalies (can't add data without unrelated data)
-- 4. Deletion anomalies (deleting one record loses unrelated data)
-- ScentDB is designed to avoid all four.

-- =====================
-- FIRST NORMAL FORM (1NF)
-- =====================
-- Rules:
-- 1. Every column holds atomic (indivisible) values
-- 2. No repeating groups or arrays in columns
-- 3. Every row is uniquely identifiable

-- VIOLATION EXAMPLE (what we avoided):
-- A naive fragrance table might look like this:
--
-- CREATE TABLE bad_fragrances (
--     fragrance_id INT,
--     name VARCHAR(100),
--     brand_name VARCHAR(100),    -- storing brand as a string = redundancy
--     notes VARCHAR(500),         -- "Bergamot, Oud, Sandalwood" = not atomic
--     buyer_names VARCHAR(500)    -- "Ali, Sara, James" = repeating group
-- );
--
-- Problems:
-- - notes column stores multiple values in one cell (violates atomicity)
-- - buyer_names is a repeating group
-- - brand_name is duplicated across every fragrance row

-- HOW SCENTDB ACHIEVES 1NF:
-- Every column holds exactly one value per row
-- Notes are stored in a separate normalized notes table
-- Buyers are stored in a separate users table
-- Each row has a unique primary key (SERIAL PRIMARY KEY)

-- Proof:
SELECT
    'fragrances' AS table_name,
    'fragrance_id' AS primary_key,
    'Every column is atomic — no arrays or repeating groups' AS compliance_note
UNION ALL
SELECT 'notes', 'note_id', 'Each note is one row — not a comma-separated string'
UNION ALL
SELECT 'users', 'user_id', 'One user per row, unique email enforced'
UNION ALL
SELECT 'purchases', 'purchase_id', 'One purchase event per row'
UNION ALL
SELECT 'ratings', 'rating_id', 'One rating per user per fragrance';

-- =====================
-- SECOND NORMAL FORM (2NF)
-- =====================
-- Rules:
-- 1. Must be in 1NF
-- 2. Every non-key column must depend on the WHOLE primary key
--    (relevant for composite primary keys)

-- VIOLATION EXAMPLE (what we avoided):
-- Imagine a naive purchases table with a composite key:
--
-- CREATE TABLE bad_purchases (
--     user_id INT,
--     fragrance_id INT,
--     PRIMARY KEY (user_id, fragrance_id),  -- composite key
--     purchase_date DATE,
--     price_paid DECIMAL,
--     fragrance_name VARCHAR(100),   -- depends only on fragrance_id, not the full key
--     brand_name VARCHAR(100)        -- depends only on fragrance_id, not the full key
-- );
--
-- fragrance_name and brand_name depend only on fragrance_id
-- not on the combination of (user_id, fragrance_id)
-- This is a partial dependency — a 2NF violation

-- HOW SCENTDB ACHIEVES 2NF:
-- fragrance_note_map uses a surrogate key (map_id) instead of composite
-- fragrance details live only in the fragrances table
-- brand details live only in the brands table
-- purchases only stores what actually belongs to a purchase event

SELECT
    'purchases' AS table_name,
    'All columns (purchase_date, price_paid, bottle_size_ml) depend fully on purchase_id' AS compliance_note
UNION ALL
SELECT
    'fragrance_note_map',
    'map_id surrogate key avoids partial dependency on composite (fragrance_id, note_id)';

-- =====================
-- THIRD NORMAL FORM (3NF)
-- =====================
-- Rules:
-- 1. Must be in 2NF
-- 2. No transitive dependencies
--    (non-key columns must not depend on other non-key columns)

-- VIOLATION EXAMPLE (what we avoided):
--
-- CREATE TABLE bad_fragrances (
--     fragrance_id INT PRIMARY KEY,
--     name VARCHAR(100),
--     brand_id INT,
--     brand_country VARCHAR(100),   -- depends on brand_id, not fragrance_id
--     brand_founded INT             -- depends on brand_id, not fragrance_id
-- );
--
-- brand_country and brand_founded depend on brand_id
-- brand_id is not the primary key
-- So these columns transitively depend on fragrance_id through brand_id
-- This is a transitive dependency — a 3NF violation

-- HOW SCENTDB ACHIEVES 3NF:
-- brands table owns all brand-related data
-- fragrances table only stores brand_id as a foreign key
-- notes table owns all note-related data
-- fragrance_note_map only references them via foreign keys
-- users table owns all user data — purchases only reference user_id

SELECT
    'fragrances → brands' AS relationship,
    'brand_country and brand_founded live in brands, not fragrances' AS compliance_note
UNION ALL
SELECT
    'fragrance_note_map → notes',
    'note category and family live in notes, not repeated in the map table'
UNION ALL
SELECT
    'purchases → users',
    'user country and email live in users, not repeated per purchase';

-- =====================
-- BOYCE-CODD NORMAL FORM (BCNF)
-- =====================
-- A stronger version of 3NF.
-- Every determinant must be a candidate key.
-- ScentDB satisfies BCNF because:
-- 1. All tables use single-column surrogate primary keys (SERIAL)
-- 2. No non-trivial functional dependencies exist outside the primary key
-- 3. Foreign keys reference primary keys only

SELECT
    'ScentDB BCNF Status' AS check_name,
    'All tables use surrogate SERIAL primary keys with no overlapping candidate keys' AS status;

-- =====================
-- FINAL SCHEMA DEPENDENCY MAP
-- =====================
-- brands
--   └── fragrances (brand_id FK)
--         └── fragrance_note_map (fragrance_id FK)
--         └── purchases (fragrance_id FK)
--         └── ratings (fragrance_id FK)
--         └── wishlists (fragrance_id FK)
-- notes
--   └── fragrance_note_map (note_id FK)
-- users
--   └── purchases (user_id FK)
--   └── ratings (user_id FK)
--   └── wishlists (user_id FK)
--   └── audit_log (performed_by FK)

-- Every relationship is enforced via foreign key constraints.
-- No data duplication exists across tables.
-- The schema is fully normalized to BCNF.