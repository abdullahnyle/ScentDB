// ScentDB: Advanced Graph Queries
// =====================
// These queries go deeper than basic lookups and recommendations.
// They model real business problems — churn detection, market basket
// analysis, influencer identification, and price sensitivity mapping.
// The kind of analysis a business analyst would actually be asked to do.
// =====================

// =====================
// CHURN DETECTION
// =====================
// Users who have wishlisted fragrances but haven't purchased anything
// in the last 90 days are at risk of losing interest entirely.
// Catching them early is cheaper than re-acquiring them later.

MATCH (u:User)-[:WISHLISTED]->(f:Fragrance)
WHERE NOT (u)-[:PURCHASED]->(f)
AND NOT EXISTS {
    MATCH (u)-[p:PURCHASED]->(:Fragrance)
    WHERE p.date >= "2024-04-01"
}
RETURN u.username AS at_risk_user,
       u.country,
       COUNT(f) AS wishlist_items_unpurchased,
       COLLECT(f.name) AS what_they_want
ORDER BY wishlist_items_unpurchased DESC;

// =====================
// MARKET BASKET ANALYSIS
// =====================
// Which fragrances are most commonly purchased together?
// This is the "customers who bought X also bought Y" logic
// that every e-commerce recommendation engine runs on.
// In SQL this needs a self-join on purchases — messy and slow at scale.
// In Neo4j it's just following the natural connections.

MATCH (u:User)-[:PURCHASED]->(f1:Fragrance),
      (u)-[:PURCHASED]->(f2:Fragrance)
WHERE f1.fragrance_id < f2.fragrance_id
RETURN f1.name AS fragrance_a,
       f2.name AS fragrance_b,
       COUNT(u) AS bought_together,
       COLLECT(u.username) AS buyers
ORDER BY bought_together DESC;

// Which brand combinations appear most in the same collection?
MATCH (u:User)-[:PURCHASED]->(f1:Fragrance)-[:MADE_BY]->(b1:Brand),
      (u)-[:PURCHASED]->(f2:Fragrance)-[:MADE_BY]->(b2:Brand)
WHERE b1.name < b2.name
RETURN b1.name AS brand_a,
       b2.name AS brand_b,
       COUNT(u) AS users_own_both,
       COLLECT(u.username) AS collectors
ORDER BY users_own_both DESC;

// =====================
// INFLUENCER IDENTIFICATION
// =====================
// Some users punch above their weight — their ratings influence
// what others go on to purchase. Finding these users matters
// because they are the ones worth engaging with first when
// launching a new fragrance.

// Users whose highly rated fragrances ended up on others' wishlists
MATCH (influencer:User)-[r:RATED]->(f:Fragrance)
WHERE r.score >= 8
MATCH (other:User)-[:WISHLISTED]->(f)
WHERE influencer.user_id <> other.user_id
RETURN influencer.username AS influencer,
       influencer.collector_level,
       COUNT(DISTINCT other) AS users_influenced,
       COUNT(DISTINCT f) AS fragrances_they_drove_interest_in,
       COLLECT(DISTINCT f.name) AS those_fragrances
ORDER BY users_influenced DESC;

// Users with the highest average rating who also own the most
// This combination — taste + breadth — signals a true community anchor
MATCH (u:User)-[r:RATED]->(f:Fragrance)
WITH u, AVG(r.score) AS avg_score, COUNT(r) AS ratings_given
MATCH (u)-[:PURCHASED]->(p:Fragrance)
WITH u, avg_score, ratings_given, COUNT(p) AS collection_size
RETURN u.username,
       u.collector_level,
       u.country,
       ROUND(avg_score, 2) AS avg_rating,
       ratings_given,
       collection_size,
       ROUND((avg_score * 0.4) + (collection_size * 0.4) + (ratings_given * 0.2), 2) AS influence_score
ORDER BY influence_score DESC;

// =====================
// PRICE SENSITIVITY MAPPING
// =====================
// Understanding where each user sits on the price curve
// helps with targeted recommendations — don't recommend
// a $500 bottle to someone whose ceiling is clearly $100.

MATCH (u:User)-[p:PURCHASED]->(f:Fragrance)
WITH u,
     MIN(f.price_usd) AS cheapest_bought,
     MAX(f.price_usd) AS most_expensive_bought,
     AVG(f.price_usd) AS avg_price,
     COUNT(f) AS total_purchases
RETURN u.username,
       u.country,
       cheapest_bought,
       most_expensive_bought,
       ROUND(avg_price, 2) AS avg_spend_per_bottle,
       total_purchases,
       CASE
           WHEN avg_price > 300 THEN "Ultra Premium"
           WHEN avg_price > 150 THEN "Premium"
           WHEN avg_price > 80  THEN "Mid Range"
           ELSE "Budget Conscious"
       END AS spending_tier
ORDER BY avg_price DESC;

// Now use those tiers to generate tier-appropriate recommendations
// Don't recommend Creed to someone in the Budget Conscious tier
MATCH (u:User)-[:PURCHASED]->(owned:Fragrance)
WITH u, AVG(owned.price_usd) AS avg_spend
MATCH (rec:Fragrance)
WHERE NOT (u)-[:PURCHASED]->(rec)
AND rec.price_usd <= avg_spend * 1.3
AND rec.price_usd >= avg_spend * 0.7
RETURN u.username AS user,
       ROUND(avg_spend, 2) AS their_usual_range,
       rec.name AS affordable_recommendation,
       rec.brand,
       rec.price_usd
ORDER BY u.username, rec.price_usd DESC;

// =====================
// TASTE EVOLUTION TRACKING
// =====================
// Do users start with cheaper fragrances and trade up over time?
// Or do they jump straight into luxury and stay there?
// Purchase date ordering reveals the journey.

MATCH (u:User)-[p:PURCHASED]->(f:Fragrance)
WITH u, f, p
ORDER BY u.user_id, p.date
WITH u,
     COLLECT(f.name) AS purchase_journey,
     COLLECT(f.price_usd) AS price_journey,
     COLLECT(p.date) AS date_journey
RETURN u.username,
       purchase_journey AS fragrances_in_order,
       price_journey AS prices_in_order,
       date_journey AS dates,
       purchase_journey[0] AS first_fragrance_ever,
       purchase_journey[-1] AS most_recent_fragrance;

// =====================
// CROSS SELLING OPPORTUNITIES
// =====================
// Users who own a fragrance but haven't tried others from the same brand
// These are the easiest conversions — brand trust is already established.

MATCH (u:User)-[:PURCHASED]->(f:Fragrance)-[:MADE_BY]->(b:Brand)
MATCH (b)<-[:MADE_BY]-(other:Fragrance)
WHERE NOT (u)-[:PURCHASED]->(other)
AND other.fragrance_id <> f.fragrance_id
RETURN u.username AS user,
       b.name AS brand_they_trust,
       f.name AS fragrance_they_own,
       other.name AS untried_from_same_brand,
       other.price_usd
ORDER BY u.username, b.name;

// =====================
// GEOGRAPHIC TASTE PATTERNS
// =====================
// Do users from the same country gravitate toward similar fragrances?
// This feeds directly into the market_trends MongoDB collection —
// ground-truth behavioral data validating the trend reports.

MATCH (u:User)-[r:RATED]->(f:Fragrance)
WITH u.country AS country,
     f.name AS fragrance,
     f.brand AS brand,
     AVG(r.score) AS avg_country_rating,
     COUNT(r) AS rating_count
WHERE rating_count >= 1
RETURN country,
       fragrance,
       brand,
       ROUND(avg_country_rating, 2) AS avg_rating,
       rating_count
ORDER BY country, avg_rating DESC;

// Which note families are most loved by country?
MATCH (u:User)-[r:RATED]->(f:Fragrance)-[:HAS_NOTE]->(n:Note)
WHERE r.score >= 8
RETURN u.country,
       n.family AS note_family,
       COUNT(r) AS high_ratings_involving_this_family,
       COLLECT(DISTINCT f.name) AS fragrances_loved
ORDER BY u.country, high_ratings_involving_this_family DESC;