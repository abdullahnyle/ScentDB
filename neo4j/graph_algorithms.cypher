// ScentDB: Graph Algorithms
// =====================
// This file uses Neo4j's graph structure to run algorithms that
// would be practically impossible in a relational database.
// PageRank finds the most influential fragrances in the network.
// Centrality finds the users who hold the community together.
// Path finding traces how any two fragrances are connected.
// These aren't academic exercises — every major recommendation
// engine from Spotify to Amazon runs some version of these.
// =====================

// =====================
// DEGREE CENTRALITY
// =====================
// The simplest influence metric — how many direct connections
// does each node have? A fragrance with high degree centrality
// is one that shows up everywhere: purchased, rated, wishlisted,
// similar to others. It's the platform's anchor product.

MATCH (f:Fragrance)
OPTIONAL MATCH (f)<-[r1:PURCHASED]-()
OPTIONAL MATCH (f)<-[r2:RATED]-()
OPTIONAL MATCH (f)<-[r3:WISHLISTED]-()
OPTIONAL MATCH (f)-[r4:SIMILAR_TO]-()
OPTIONAL MATCH (f)<-[r5:SIMILAR_TO]-()
RETURN f.name AS fragrance,
       f.brand,
       COUNT(DISTINCT r1) AS purchased_by,
       COUNT(DISTINCT r2) AS rated_by,
       COUNT(DISTINCT r3) AS wishlisted_by,
       COUNT(DISTINCT r4) + COUNT(DISTINCT r5) AS similarity_connections,
       COUNT(DISTINCT r1) + COUNT(DISTINCT r2) +
       COUNT(DISTINCT r3) + COUNT(DISTINCT r4) +
       COUNT(DISTINCT r5) AS total_degree
ORDER BY total_degree DESC;

// Same analysis for users — who is the most connected person
// in the community? Most connected users are the ones whose
// behavior you want to track most closely.
MATCH (u:User)
OPTIONAL MATCH (u)-[r1:PURCHASED]->()
OPTIONAL MATCH (u)-[r2:RATED]->()
OPTIONAL MATCH (u)-[r3:WISHLISTED]->()
OPTIONAL MATCH (u)-[r4:SIMILAR_TASTE]->()
RETURN u.username,
       u.collector_level,
       u.country,
       COUNT(DISTINCT r1) AS purchases,
       COUNT(DISTINCT r2) AS ratings,
       COUNT(DISTINCT r3) AS wishlist_items,
       COUNT(DISTINCT r4) AS taste_connections,
       COUNT(DISTINCT r1) + COUNT(DISTINCT r2) +
       COUNT(DISTINCT r3) + COUNT(DISTINCT r4) AS total_degree
ORDER BY total_degree DESC;

// =====================
// BETWEENNESS CENTRALITY (MANUAL APPROXIMATION)
// =====================
// True betweenness centrality requires the GDS plugin which needs
// Neo4j Enterprise. This approximation finds nodes that sit between
// the most pairs of other nodes — the bridges in the network.
// A fragrance with high betweenness is one that connects otherwise
// separate taste communities. It's the crossover product.

// Which fragrances connect users who otherwise have no overlap?
MATCH (u1:User)-[:PURCHASED]->(f:Fragrance)<-[:PURCHASED]-(u2:User)
WHERE u1.user_id < u2.user_id
AND NOT (u1)-[:SIMILAR_TASTE]-(u2)
RETURN f.name AS bridge_fragrance,
       f.brand,
       COUNT(DISTINCT [u1.username, u2.username]) AS pairs_connected,
       COLLECT(DISTINCT u1.username + " & " + u2.username) AS connected_pairs
ORDER BY pairs_connected DESC;

// Which notes act as bridges between different fragrance families?
// A note that appears in both citrus and oriental fragrances
// is a bridge ingredient — it can introduce users from one
// family to another.
MATCH (f1:Fragrance)-[:HAS_NOTE]->(n:Note)<-[:HAS_NOTE]-(f2:Fragrance)
WHERE f1.fragrance_id < f2.fragrance_id
WITH n,
     COLLECT(DISTINCT f1.name + " & " + f2.name) AS fragrance_pairs,
     COUNT(DISTINCT f1) + COUNT(DISTINCT f2) AS fragrances_connected
RETURN n.name AS bridge_note,
       n.family,
       fragrances_connected,
       fragrance_pairs
ORDER BY fragrances_connected DESC;

// =====================
// SHORTEST PATH
// =====================
// How is any fragrance connected to any other through
// the network of users, purchases, and similarities?
// This is the "six degrees of separation" applied to fragrances.

// Shortest path between Aventus and Black Orchid
// through any type of relationship
MATCH path = shortestPath(
    (f1:Fragrance {name: "Aventus"})-[*]-(f2:Fragrance {name: "Black Orchid"})
)
RETURN path,
       LENGTH(path) AS hops,
       [node IN NODES(path) | 
           CASE 
               WHEN node:Fragrance THEN "Fragrance: " + node.name
               WHEN node:User THEN "User: " + node.username
               WHEN node:Note THEN "Note: " + node.name
               WHEN node:Brand THEN "Brand: " + node.name
               ELSE "Unknown"
           END
       ] AS path_explained;

// All paths within 3 hops between two users
// Shows how tightly connected the community really is
MATCH path = allShortestPaths(
    (u1:User {username: "scentlover1"})-[*]-(u2:User {username: "oud_addict"})
)
RETURN path,
       LENGTH(path) AS connection_length,
       [node IN NODES(path) |
           CASE
               WHEN node:Fragrance THEN node.name
               WHEN node:User THEN node.username
               WHEN node:Note THEN node.name
               ELSE ""
           END
       ] AS how_theyre_connected;

// =====================
// CLUSTERING COEFFICIENT
// =====================
// Are users in tight clusters (everyone knows everyone)
// or loosely connected (long chains)?
// High clustering = strong community = better word of mouth.
// Low clustering = fragmented market = harder to retain users.

// Find triangles in the user-fragrance graph
// A triangle here means: user A and user B both bought fragrance X
// AND user A and user B have a similar taste relationship
// These triangles are the strongest signal of genuine community.
MATCH (u1:User)-[:PURCHASED]->(f:Fragrance)<-[:PURCHASED]-(u2:User)
MATCH (u1)-[:SIMILAR_TASTE]-(u2)
WHERE u1.user_id < u2.user_id
RETURN u1.username AS user_a,
       u2.username AS user_b,
       f.name AS shared_fragrance,
       "Triangle — strong community signal" AS pattern_type;

// =====================
// PAGERANK APPROXIMATION
// =====================
// PageRank asks: if a user randomly clicked through the similarity
// graph, which fragrance would they land on most often?
// High PageRank = most "central" fragrance in the taste network.
// This is essentially what Spotify uses to rank songs in discovery.

// Manual PageRank approximation — iterate through similarity connections
// weighted by how many users rated each fragrance highly
MATCH (f:Fragrance)
OPTIONAL MATCH (f)<-[r:RATED]-(u:User)
WITH f,
     COUNT(r) AS rating_count,
     COALESCE(AVG(r.score), 0) AS avg_score
OPTIONAL MATCH (f)-[:SIMILAR_TO]->(similar:Fragrance)
WITH f,
     rating_count,
     avg_score,
     COUNT(similar) AS outgoing_similarities
OPTIONAL MATCH (:Fragrance)-[:SIMILAR_TO]->(f)
WITH f,
     rating_count,
     avg_score,
     outgoing_similarities,
     COUNT(*) AS incoming_similarities
RETURN f.name AS fragrance,
       f.brand,
       rating_count,
       ROUND(avg_score, 2) AS avg_rating,
       incoming_similarities AS referenced_by_others,
       outgoing_similarities AS references_others,
       ROUND(
           (avg_score * 0.4) +
           (rating_count * 0.3) +
           (incoming_similarities * 0.3),
           3
       ) AS pagerank_approximation
ORDER BY pagerank_approximation DESC;

// =====================
// COLD START PROBLEM
// =====================
// New users have no purchase history so the recommendation engine
// has nothing to work with. This query handles cold start by
// recommending the highest PageRank fragrances to new users
// filtered by their stated country — using market trend data
// as a proxy for taste until behavioral data accumulates.

// For a new user from Pakistan — recommend based on
// what Pakistani users with similar demographics rate highly
MATCH (existing:User {country: "Pakistan"})-[r:RATED]->(f:Fragrance)
WHERE r.score >= 7
WITH f,
     AVG(r.score) AS country_avg_score,
     COUNT(r) AS local_rating_count
RETURN f.name AS cold_start_recommendation,
       f.brand,
       f.price_usd,
       ROUND(country_avg_score, 2) AS avg_score_in_your_country,
       local_rating_count AS rated_by_users_like_you
ORDER BY country_avg_score DESC, local_rating_count DESC;

// =====================
// NETWORK HEALTH METRICS
// =====================
// A quick dashboard of how healthy the overall graph is.
// Are users engaged? Is the catalog well connected?
// Are there isolated nodes with no relationships?

MATCH (u:User)
OPTIONAL MATCH (u)-[:PURCHASED]->()
OPTIONAL MATCH (u)-[:RATED]->()
WITH u,
     COUNT(DISTINCT u) AS has_purchases,
     COUNT(DISTINCT u) AS has_ratings
RETURN
    "Total Users" AS metric,
    COUNT(u) AS value
UNION
MATCH (:User)-[:PURCHASED]->()
RETURN "Total Purchases" AS metric, COUNT(*) AS value
UNION
MATCH (:User)-[:RATED]->()
RETURN "Total Ratings" AS metric, COUNT(*) AS value
UNION
MATCH (:User)-[:WISHLISTED]->()
RETURN "Total Wishlist Items" AS metric, COUNT(*) AS value
UNION
MATCH (:Fragrance)-[:SIMILAR_TO]->()
RETURN "Similarity Connections" AS metric, COUNT(*) AS value
UNION
MATCH (:User)-[:SIMILAR_TASTE]->()
RETURN "User Taste Connections" AS metric, COUNT(*) AS value;