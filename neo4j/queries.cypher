// ScentDB: Neo4j Queries
// =====================
// This is where the graph pays off. These queries would require
// multiple expensive joins in PostgreSQL. In Neo4j they read
// almost like plain English — follow this connection, then that one,
// return what you find.
// =====================

// =====================
// BASIC LOOKUPS
// =====================

// What has a specific user purchased?
MATCH (u:User {username: "scentlover1"})-[:PURCHASED]->(f:Fragrance)
RETURN u.username, f.name, f.brand, f.price_usd
ORDER BY f.price_usd DESC;

// What is on a user's wishlist that they haven't bought yet?
MATCH (u:User {username: "scentlover1"})-[:WISHLISTED]->(f:Fragrance)
WHERE NOT (u)-[:PURCHASED]->(f)
RETURN u.username, f.name, f.brand, f.price_usd
ORDER BY f.price_usd DESC;

// Which fragrances has a user both purchased AND rated highly?
MATCH (u:User {username: "scentlover1"})-[:PURCHASED]->(f:Fragrance)
MATCH (u)-[r:RATED]->(f)
WHERE r.score >= 8
RETURN u.username, f.name, r.score, r.review
ORDER BY r.score DESC;

// =====================
// RECOMMENDATION ENGINE
// =====================

// Core recommendation — find what similar users bought
// that this user hasn't tried yet
MATCH (u:User {username: "scentlover1"})-[:SIMILAR_TASTE]->(similar_user:User)
MATCH (similar_user)-[:PURCHASED]->(f:Fragrance)
WHERE NOT (u)-[:PURCHASED]->(f)
AND NOT (u)-[:RATED]->(f)
RETURN f.name AS recommended_fragrance,
       f.brand,
       f.price_usd,
       similar_user.username AS recommended_by
ORDER BY f.price_usd DESC;

// Note-based recommendation — find fragrances sharing notes
// with what this user already rated highly
MATCH (u:User {username: "scentlover1"})-[r:RATED]->(liked:Fragrance)
WHERE r.score >= 8
MATCH (liked)-[:HAS_NOTE]->(n:Note)<-[:HAS_NOTE]-(recommended:Fragrance)
WHERE NOT (u)-[:PURCHASED]->(recommended)
AND NOT (u)-[:RATED]->(recommended)
RETURN recommended.name AS fragrance,
       recommended.brand,
       recommended.price_usd,
       COUNT(n) AS shared_notes,
       COLLECT(n.name) AS notes_in_common
ORDER BY shared_notes DESC;

// Similarity chain — fragrances similar to what user likes
MATCH (u:User {username: "scentlover1"})-[:RATED {score: 9}]->(f:Fragrance)
MATCH (f)-[s:SIMILAR_TO]->(rec:Fragrance)
WHERE NOT (u)-[:PURCHASED]->(rec)
RETURN f.name AS because_you_liked,
       rec.name AS you_might_like,
       rec.brand,
       rec.price_usd,
       s.reason,
       s.similarity_score
ORDER BY s.similarity_score DESC;

// =====================
// NETWORK ANALYSIS
// =====================

// Which fragrance is most connected — most purchased, rated, wishlisted
MATCH (f:Fragrance)
OPTIONAL MATCH (f)<-[:PURCHASED]-(u1:User)
OPTIONAL MATCH (f)<-[:RATED]-(u2:User)
OPTIONAL MATCH (f)<-[:WISHLISTED]-(u3:User)
RETURN f.name,
       f.brand,
       COUNT(DISTINCT u1) AS times_purchased,
       COUNT(DISTINCT u2) AS times_rated,
       COUNT(DISTINCT u3) AS times_wishlisted,
       COUNT(DISTINCT u1) + COUNT(DISTINCT u2) + COUNT(DISTINCT u3) AS total_engagement
ORDER BY total_engagement DESC;

// Which notes create the most connections across the catalog
MATCH (n:Note)<-[:HAS_NOTE]-(f:Fragrance)
RETURN n.name AS note,
       n.family,
       n.layer,
       COUNT(f) AS fragrances_using_note
ORDER BY fragrances_using_note DESC;

// Find all fragrances within 2 hops of what a user purchased
// This is the classic graph traversal — impossible to do elegantly in SQL
MATCH (u:User {username: "scentlover1"})-[:PURCHASED]->(f:Fragrance)
MATCH (f)-[:SIMILAR_TO*1..2]->(discovered:Fragrance)
WHERE NOT (u)-[:PURCHASED]->(discovered)
RETURN DISTINCT discovered.name AS fragrance,
                discovered.brand,
                discovered.price_usd
ORDER BY discovered.price_usd DESC;

// =====================
// BRAND ANALYSIS
// =====================

// Brand loyalty — users who bought multiple fragrances from same brand
MATCH (u:User)-[:PURCHASED]->(f:Fragrance)-[:MADE_BY]->(b:Brand)
WITH u, b, COUNT(f) AS purchases_from_brand
WHERE purchases_from_brand > 1
RETURN u.username,
       b.name AS brand,
       purchases_from_brand
ORDER BY purchases_from_brand DESC;

// Which brand has the most engaged community?
MATCH (b:Brand)<-[:MADE_BY]-(f:Fragrance)
OPTIONAL MATCH (f)<-[:RATED]-(u:User)
RETURN b.name AS brand,
       b.tier,
       COUNT(DISTINCT f) AS fragrance_count,
       COUNT(DISTINCT u) AS unique_raters,
       ROUND(AVG(u.age), 1) AS avg_rater_age
ORDER BY unique_raters DESC;

// =====================
// USER COMMUNITY ANALYSIS
// =====================

// Find users with the most similar taste profiles
MATCH (u1:User)-[s:SIMILAR_TASTE]->(u2:User)
RETURN u1.username AS user,
       u2.username AS similar_to,
       s.overlap_score,
       s.reason
ORDER BY s.overlap_score DESC;

// Community clusters — users connected through shared fragrance purchases
MATCH (u1:User)-[:PURCHASED]->(f:Fragrance)<-[:PURCHASED]-(u2:User)
WHERE u1.user_id < u2.user_id
RETURN u1.username AS user1,
       u2.username AS user2,
       COLLECT(f.name) AS fragrances_both_own,
       COUNT(f) AS overlap_count
ORDER BY overlap_count DESC;

// Which country has the most active fragrance community?
MATCH (u:User)-[:PURCHASED]->(f:Fragrance)
RETURN u.country,
       COUNT(DISTINCT u) AS active_buyers,
       COUNT(f) AS total_purchases,
       ROUND(AVG(f.price_usd), 2) AS avg_fragrance_price
ORDER BY total_purchases DESC;

// =====================
// WISHLIST INTELLIGENCE
// =====================

// Most wishlisted fragrances that nobody has bought yet
// These represent the highest unmet demand in the catalog
MATCH (f:Fragrance)<-[:WISHLISTED]-(u:User)
WHERE NOT (u)-[:PURCHASED]->(f)
RETURN f.name AS fragrance,
       f.brand,
       f.price_usd,
       COUNT(u) AS users_wanting_it
ORDER BY users_wanting_it DESC;

// Users whose wishlist matches what similar users already own
// Prime targets for a "your friends have this" nudge
MATCH (u1:User)-[:SIMILAR_TASTE]->(u2:User)
MATCH (u1)-[:WISHLISTED]->(f:Fragrance)
MATCH (u2)-[:PURCHASED]->(f)
WHERE NOT (u1)-[:PURCHASED]->(f)
RETURN u1.username AS user,
       f.name AS wishlisted_fragrance,
       u2.username AS friend_who_owns_it,
       f.price_usd
ORDER BY f.price_usd DESC;