-- ScentDB: Transaction Management
-- =====================
-- Transactions are what separate a toy database from a production one.
-- Every purchase on a real fragrance platform touches multiple tables
-- simultaneously — inventory, purchases, audit logs, user points.
-- If any one of those writes fails, all of them need to roll back.
-- Without transactions, you end up with a user who was charged
-- but has no purchase record, or a stock count that went negative.
-- This file demonstrates full ACID transaction handling for ScentDB.
-- =====================

-- =====================
-- BASIC TRANSACTION STRUCTURE
-- =====================

-- A simple purchase transaction
-- Either everything succeeds or nothing does
BEGIN;

    -- Step 1: Record the purchase
    INSERT INTO purchases (user_id, fragrance_id, purchase_date, price_paid, bottle_size_ml)
    VALUES (1, 7, CURRENT_DATE, 290.00, 100);

    -- Step 2: Record the rating if they reviewed at point of purchase
    INSERT INTO ratings (user_id, fragrance_id, score, review_text)
    VALUES (1, 7, 8, 'Bought this on a whim. Dark and complex, grows on you.');

    -- Step 3: Remove from wishlist since they bought it
    DELETE FROM wishlists
    WHERE user_id = 1 AND fragrance_id = 7;

    -- Step 4: Audit log entry is handled automatically by the trigger
    -- but we can add a manual note for the transaction itself
    INSERT INTO audit_log (table_name, action, performed_by, details)
    VALUES ('purchases', 'TRANSACTION_COMPLETE', 1,
            'Full purchase flow completed: purchase + rating + wishlist cleanup');

COMMIT;

-- =====================
-- TRANSACTION WITH ROLLBACK
-- =====================
-- What happens when something goes wrong mid-transaction?
-- This simulates a failed purchase where the rating insert fails
-- and we need to roll back the entire thing.

BEGIN;

    INSERT INTO purchases (user_id, fragrance_id, purchase_date, price_paid, bottle_size_ml)
    VALUES (2, 8, CURRENT_DATE, 110.00, 75);

    -- This will fail because score 11 violates the CHECK constraint
    -- score must be between 1 and 10
    INSERT INTO ratings (user_id, fragrance_id, score, review_text)
    VALUES (2, 8, 11, 'This would fail the constraint check.');

    -- Because the above fails, this entire block rolls back
    -- The purchase insert above never actually commits
    COMMIT;

-- Catch the error and roll back cleanly
ROLLBACK;

-- Verify the purchase was not recorded
SELECT * FROM purchases WHERE user_id = 2 AND fragrance_id = 8;

-- =====================
-- SAVEPOINTS
-- =====================
-- Savepoints let you roll back to a specific point within a transaction
-- without rolling back the entire thing.
-- Useful when you have a multi-step process where early steps
-- should be preserved even if later steps fail.

BEGIN;

    -- Savepoint A: after the purchase is recorded
    INSERT INTO purchases (user_id, fragrance_id, purchase_date, price_paid, bottle_size_ml)
    VALUES (3, 4, CURRENT_DATE, 95.00, 100);

    SAVEPOINT after_purchase;

    -- Try to add to a loyalty points table that may not exist yet
    -- This will fail but we only want to roll back to the savepoint
    -- not lose the purchase
    INSERT INTO audit_log (table_name, action, performed_by, details)
    VALUES ('loyalty_points', 'INSERT', 3, 'Attempted loyalty points credit — system unavailable');

    SAVEPOINT after_loyalty_attempt;

    -- Roll back only the loyalty attempt, keep the purchase
    ROLLBACK TO SAVEPOINT after_purchase;

    -- Continue with the rest of the transaction
    INSERT INTO ratings (user_id, fragrance_id, score, review_text)
    VALUES (3, 4, 7, 'Decent but fades faster than expected.');

COMMIT;

-- =====================
-- CONCURRENT TRANSACTION HANDLING
-- =====================
-- What happens when two users try to buy the last bottle
-- of a limited edition fragrance at the same time?
-- This is where isolation levels matter.

-- Session A starts first
BEGIN;
    -- Check stock (imagine we had an inventory table)
    -- Session A sees 1 bottle available
    SELECT fragrance_id, name, price_usd
    FROM fragrances
    WHERE fragrance_id = 1
    FOR UPDATE;  -- Lock this row so Session B has to wait

    -- Session A records their purchase
    INSERT INTO purchases (user_id, fragrance_id, purchase_date, price_paid, bottle_size_ml)
    VALUES (4, 1, CURRENT_DATE, 495.00, 100);

COMMIT;
-- Only after Session A commits does Session B get to proceed
-- By that point it can check and see stock is 0

-- =====================
-- ISOLATION LEVELS
-- =====================
-- PostgreSQL supports four isolation levels.
-- Each one trades consistency for performance differently.

-- READ COMMITTED (PostgreSQL default)
-- Each query in the transaction sees the latest committed data
-- Good for most analytical queries
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN;
    SELECT AVG(price_paid) FROM purchases;
    -- If another session commits a purchase between these two queries
    -- the second query will see the new data
    SELECT COUNT(*) FROM purchases;
COMMIT;

-- REPEATABLE READ
-- Once you read a row, it stays the same for the entire transaction
-- even if someone else commits changes to it
-- Good for reports that need consistent snapshots
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN;
    -- This will return the same results even if new purchases
    -- are committed while this transaction is running
    SELECT user_id,
           COUNT(*) AS purchase_count,
           SUM(price_paid) AS total_spent
    FROM purchases
    GROUP BY user_id;
COMMIT;

-- SERIALIZABLE
-- The strictest level — transactions behave as if they ran one at a time
-- Use for financial calculations where absolute consistency matters
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN;
    -- Calculate revenue for a financial report
    -- Nobody can touch the purchases table while this runs
    SELECT
        TO_CHAR(purchase_date, 'YYYY-MM') AS month,
        COUNT(*) AS transactions,
        SUM(price_paid) AS revenue,
        ROUND(AVG(price_paid), 2) AS avg_order_value
    FROM purchases
    GROUP BY TO_CHAR(purchase_date, 'YYYY-MM')
    ORDER BY month;
COMMIT;

-- =====================
-- TRANSACTION MONITORING
-- =====================
-- How do you know if transactions are causing problems?
-- These queries let you see what's happening inside PostgreSQL
-- while transactions are running.

-- See all currently active transactions
SELECT pid,
       usename,
       application_name,
       state,
       wait_event_type,
       wait_event,
       query_start,
       state_change,
       LEFT(query, 80) AS current_query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;

-- Find long running transactions that might be holding locks
SELECT pid,
       now() - pg_stat_activity.query_start AS duration,
       query,
       state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > INTERVAL '5 minutes';

-- See which transactions are blocking others
SELECT blocked_locks.pid AS blocked_pid,
       blocked_activity.usename AS blocked_user,
       blocking_locks.pid AS blocking_pid,
       blocking_activity.usename AS blocking_user,
       blocked_activity.query AS blocked_statement,
       blocking_activity.query AS current_statement_in_blocking_process
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity
    ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity
    ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.GRANTED;

-- =====================
-- DEAD LOCK PREVENTION
-- =====================
-- Deadlocks happen when two transactions each hold a lock
-- the other one needs. PostgreSQL detects and kills one of them
-- automatically, but prevention is better than cure.
-- The rule: always acquire locks in the same order across transactions.

-- Safe pattern — always lock users before purchases
BEGIN;
    SELECT * FROM users WHERE user_id = 1 FOR UPDATE;
    SELECT * FROM purchases WHERE user_id = 1 FOR UPDATE;
    -- Do your work here
COMMIT;

-- This would risk a deadlock if another transaction
-- locks purchases first and then tries to lock users
-- Never do this in production:
-- BEGIN;
--     SELECT * FROM purchases WHERE user_id = 1 FOR UPDATE;
--     SELECT * FROM users WHERE user_id = 1 FOR UPDATE;
-- COMMIT;

-- =====================
-- BULK TRANSACTION PATTERN
-- =====================
-- When loading large amounts of data, wrapping inserts
-- in a single transaction is dramatically faster than
-- auto-committing each row individually.
-- The difference on 100,000 rows can be 10x speed improvement.

BEGIN;
    -- Bulk insert new fragrances for a catalog update
    INSERT INTO fragrances (name, brand_id, concentration, release_year, price_usd, gender_target)
    VALUES
        ('Silver Mountain Water', 1, 'EDP', 1995, 420.00, 'Unisex'),
        ('Tobacco Vanille', 3, 'EDP', 2007, 320.00, 'Unisex'),
        ('Y', 2, 'EDP', 2017, 105.00, 'Male'),
        ('Dylan Blue', 4, 'EDT', 2016, 85.00, 'Male'),
        ('Chance Eau Tendre', 5, 'EDP', 2002, 165.00, 'Female');

    -- Verify the count before committing
    SELECT COUNT(*) FROM fragrances;

    -- If the count looks right, commit
    -- If something looks wrong, we can still ROLLBACK here
COMMIT;