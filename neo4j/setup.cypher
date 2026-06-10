// ScentDB: Neo4j Graph Database Setup
// =====================
// Why a graph database here?
// PostgreSQL can store relationships via foreign keys, but querying
// "users who like what you like also tend to buy X" requires expensive
// multi-level joins that get slower as the dataset grows.
// Neo4j stores relationships as first-class citizens — traversing
// connections is what it was built for. The recommendation engine
// lives here because it's genuinely the right tool for the job.
// =====================

// =====================
// CLEAR EXISTING DATA
// =====================
MATCH (n) DETACH DELETE n;

// =====================
// CREATE USER NODES
// =====================
CREATE (u1:User {
  user_id: 1,
  username: "scentlover1",
  age: 24,
  country: "Pakistan",
  collector_level: "Enthusiast"
})

CREATE (u2:User {
  user_id: 2,
  username: "fragrancepro",
  age: 28,
  country: "UAE",
  collector_level: "Expert"
})

CREATE (u3:User {
  user_id: 3,
  username: "oud_addict",
  age: 31,
  country: "UK",
  collector_level: "Collector"
})

CREATE (u4:User {
  user_id: 4,
  username: "perfume_pk",
  age: 22,
  country: "Pakistan",
  collector_level: "Beginner"
})

CREATE (u5:User {
  user_id: 5,
  username: "scentseeker",
  age: 26,
  country: "Ireland",
  collector_level: "Enthusiast"
})

// =====================
// CREATE FRAGRANCE NODES
// =====================
CREATE (f1:Fragrance {
  fragrance_id: 1,
  name: "Aventus",
  brand: "Creed",
  concentration: "EDP",
  gender: "Male",
  price_usd: 495,
  release_year: 2010
})

CREATE (f2:Fragrance {
  fragrance_id: 2,
  name: "Sauvage",
  brand: "Dior",
  concentration: "EDT",
  gender: "Male",
  price_usd: 120,
  release_year: 2015
})

CREATE (f3:Fragrance {
  fragrance_id: 3,
  name: "Oud Wood",
  brand: "Tom Ford",
  concentration: "EDP",
  gender: "Unisex",
  price_usd: 310,
  release_year: 2007
})

CREATE (f4:Fragrance {
  fragrance_id: 4,
  name: "Eros",
  brand: "Versace",
  concentration: "EDT",
  gender: "Male",
  price_usd: 95,
  release_year: 2012
})

CREATE (f5:Fragrance {
  fragrance_id: 5,
  name: "Bleu de Chanel",
  brand: "Chanel",
  concentration: "EDP",
  gender: "Male",
  price_usd: 185,
  release_year: 2010
})

CREATE (f6:Fragrance {
  fragrance_id: 6,
  name: "Miss Dior",
  brand: "Dior",
  concentration: "EDP",
  gender: "Female",
  price_usd: 140,
  release_year: 2011
})

CREATE (f7:Fragrance {
  fragrance_id: 7,
  name: "Black Orchid",
  brand: "Tom Ford",
  concentration: "EDP",
  gender: "Unisex",
  price_usd: 290,
  release_year: 2006
})

CREATE (f8:Fragrance {
  fragrance_id: 8,
  name: "Allure Homme",
  brand: "Chanel",
  concentration: "EDT",
  gender: "Male",
  price_usd: 110,
  release_year: 1999
})

// =====================
// CREATE NOTE NODES
// =====================
CREATE (n1:Note { name: "Bergamot", family: "Citrus", layer: "Top" })
CREATE (n2:Note { name: "Oud", family: "Woody", layer: "Base" })
CREATE (n3:Note { name: "Sandalwood", family: "Woody", layer: "Base" })
CREATE (n4:Note { name: "Rose", family: "Floral", layer: "Middle" })
CREATE (n5:Note { name: "Ambergris", family: "Animalic", layer: "Base" })
CREATE (n6:Note { name: "Vetiver", family: "Woody", layer: "Base" })
CREATE (n7:Note { name: "Lavender", family: "Aromatic", layer: "Middle" })
CREATE (n8:Note { name: "Oakmoss", family: "Earthy", layer: "Middle" })
CREATE (n9:Note { name: "Vanilla", family: "Sweet", layer: "Base" })
CREATE (n10:Note { name: "Leather", family: "Animalic", layer: "Base" })

// =====================
// CREATE BRAND NODES
// =====================
CREATE (b1:Brand { name: "Creed", country: "France", tier: "Ultra Luxury" })
CREATE (b2:Brand { name: "Dior", country: "France", tier: "Luxury" })
CREATE (b3:Brand { name: "Tom Ford", country: "USA", tier: "Luxury" })
CREATE (b4:Brand { name: "Versace", country: "Italy", tier: "Designer" })
CREATE (b5:Brand { name: "Chanel", country: "France", tier: "Luxury" });

// =====================
// USER → FRAGRANCE RELATIONSHIPS
// =====================

// PURCHASED relationships
MATCH (u:User {user_id: 1}), (f:Fragrance {fragrance_id: 1})
CREATE (u)-[:PURCHASED {date: "2024-01-15", price_paid: 495, bottle_ml: 100}]->(f);

MATCH (u:User {user_id: 1}), (f:Fragrance {fragrance_id: 2})
CREATE (u)-[:PURCHASED {date: "2024-03-22", price_paid: 120, bottle_ml: 100}]->(f);

MATCH (u:User {user_id: 2}), (f:Fragrance {fragrance_id: 3})
CREATE (u)-[:PURCHASED {date: "2024-02-10", price_paid: 310, bottle_ml: 50}]->(f);

MATCH (u:User {user_id: 3}), (f:Fragrance {fragrance_id: 5})
CREATE (u)-[:PURCHASED {date: "2024-04-05", price_paid: 185, bottle_ml: 100}]->(f);

MATCH (u:User {user_id: 4}), (f:Fragrance {fragrance_id: 4})
CREATE (u)-[:PURCHASED {date: "2024-01-30", price_paid: 95, bottle_ml: 50}]->(f);

MATCH (u:User {user_id: 5}), (f:Fragrance {fragrance_id: 7})
CREATE (u)-[:PURCHASED {date: "2024-05-12", price_paid: 290, bottle_ml: 100}]->(f);

// RATED relationships
MATCH (u:User {user_id: 1}), (f:Fragrance {fragrance_id: 1})
CREATE (u)-[:RATED {score: 9, review: "Incredible projection and longevity. Worth every penny."}]->(f);

MATCH (u:User {user_id: 1}), (f:Fragrance {fragrance_id: 2})
CREATE (u)-[:RATED {score: 8, review: "Fresh and powerful. Great for daily wear."}]->(f);

MATCH (u:User {user_id: 2}), (f:Fragrance {fragrance_id: 3})
CREATE (u)-[:RATED {score: 10, review: "Best oud fragrance I have ever tried."}]->(f);

MATCH (u:User {user_id: 3}), (f:Fragrance {fragrance_id: 5})
CREATE (u)-[:RATED {score: 9, review: "Sophisticated and versatile. My signature scent."}]->(f);

MATCH (u:User {user_id: 4}), (f:Fragrance {fragrance_id: 4})
CREATE (u)-[:RATED {score: 7, review: "Good for the price. Longevity could be better."}]->(f);

MATCH (u:User {user_id: 5}), (f:Fragrance {fragrance_id: 7})
CREATE (u)-[:RATED {score: 8, review: "Dark and mysterious. Love wearing it in winter."}]->(f);

// WISHLISTED relationships
MATCH (u:User {user_id: 1}), (f:Fragrance {fragrance_id: 3})
CREATE (u)-[:WISHLISTED {priority: 1, added_date: "2024-05-01"}]->(f);

MATCH (u:User {user_id: 1}), (f:Fragrance {fragrance_id: 5})
CREATE (u)-[:WISHLISTED {priority: 2, added_date: "2024-05-15"}]->(f);

MATCH (u:User {user_id: 4}), (f:Fragrance {fragrance_id: 1})
CREATE (u)-[:WISHLISTED {priority: 1, added_date: "2024-06-01"}]->(f);

MATCH (u:User {user_id: 3}), (f:Fragrance {fragrance_id: 7})
CREATE (u)-[:WISHLISTED {priority: 2, added_date: "2024-04-20"}]->(f);

// =====================
// FRAGRANCE → NOTE RELATIONSHIPS
// =====================
MATCH (f:Fragrance {name: "Aventus"}), (n:Note {name: "Bergamot"})
CREATE (f)-[:HAS_NOTE {layer: "Top"}]->(n);

MATCH (f:Fragrance {name: "Aventus"}), (n:Note {name: "Oakmoss"})
CREATE (f)-[:HAS_NOTE {layer: "Middle"}]->(n);

MATCH (f:Fragrance {name: "Aventus"}), (n:Note {name: "Ambergris"})
CREATE (f)-[:HAS_NOTE {layer: "Base"}]->(n);

MATCH (f:Fragrance {name: "Sauvage"}), (n:Note {name: "Bergamot"})
CREATE (f)-[:HAS_NOTE {layer: "Top"}]->(n);

MATCH (f:Fragrance {name: "Sauvage"}), (n:Note {name: "Lavender"})
CREATE (f)-[:HAS_NOTE {layer: "Middle"}]->(n);

MATCH (f:Fragrance {name: "Sauvage"}), (n:Note {name: "Ambergris"})
CREATE (f)-[:HAS_NOTE {layer: "Base"}]->(n);

MATCH (f:Fragrance {name: "Oud Wood"}), (n:Note {name: "Oud"})
CREATE (f)-[:HAS_NOTE {layer: "Middle"}]->(n);

MATCH (f:Fragrance {name: "Oud Wood"}), (n:Note {name: "Sandalwood"})
CREATE (f)-[:HAS_NOTE {layer: "Base"}]->(n);

MATCH (f:Fragrance {name: "Bleu de Chanel"}), (n:Note {name: "Bergamot"})
CREATE (f)-[:HAS_NOTE {layer: "Top"}]->(n);

MATCH (f:Fragrance {name: "Bleu de Chanel"}), (n:Note {name: "Rose"})
CREATE (f)-[:HAS_NOTE {layer: "Middle"}]->(n);

MATCH (f:Fragrance {name: "Bleu de Chanel"}), (n:Note {name: "Vetiver"})
CREATE (f)-[:HAS_NOTE {layer: "Base"}]->(n);

MATCH (f:Fragrance {name: "Black Orchid"}), (n:Note {name: "Leather"})
CREATE (f)-[:HAS_NOTE {layer: "Base"}]->(n);

MATCH (f:Fragrance {name: "Black Orchid"}), (n:Note {name: "Vanilla"})
CREATE (f)-[:HAS_NOTE {layer: "Base"}]->(n);

// =====================
// FRAGRANCE → BRAND RELATIONSHIPS
// =====================
MATCH (f:Fragrance {brand: "Creed"}), (b:Brand {name: "Creed"})
CREATE (f)-[:MADE_BY]->(b);

MATCH (f:Fragrance {brand: "Dior"}), (b:Brand {name: "Dior"})
CREATE (f)-[:MADE_BY]->(b);

MATCH (f:Fragrance {brand: "Tom Ford"}), (b:Brand {name: "Tom Ford"})
CREATE (f)-[:MADE_BY]->(b);

MATCH (f:Fragrance {brand: "Versace"}), (b:Brand {name: "Versace"})
CREATE (f)-[:MADE_BY]->(b);

MATCH (f:Fragrance {brand: "Chanel"}), (b:Brand {name: "Chanel"})
CREATE (f)-[:MADE_BY]->(b);

// =====================
// FRAGRANCE SIMILARITY RELATIONSHIPS
// =====================
// These are based on shared notes and olfactory family
// This is what powers the recommendation engine

MATCH (f1:Fragrance {name: "Aventus"}), (f2:Fragrance {name: "Bleu de Chanel"})
CREATE (f1)-[:SIMILAR_TO {
  reason: "Both share Bergamot top note and Ambergris base",
  similarity_score: 0.74
}]->(f2);

MATCH (f1:Fragrance {name: "Oud Wood"}), (f2:Fragrance {name: "Black Orchid"})
CREATE (f1)-[:SIMILAR_TO {
  reason: "Both are dark woody orientals with leather and resinous base",
  similarity_score: 0.81
}]->(f2);

MATCH (f1:Fragrance {name: "Sauvage"}), (f2:Fragrance {name: "Bleu de Chanel"})
CREATE (f1)-[:SIMILAR_TO {
  reason: "Both are fresh aromatic masculines with citrus opening",
  similarity_score: 0.69
}]->(f2);

MATCH (f1:Fragrance {name: "Aventus"}), (f2:Fragrance {name: "Sauvage"})
CREATE (f1)-[:SIMILAR_TO {
  reason: "Both share Bergamot and Ambergris, fresh yet powerful projection",
  similarity_score: 0.61
}]->(f2);

MATCH (f1:Fragrance {name: "Black Orchid"}), (f2:Fragrance {name: "Oud Wood"})
CREATE (f1)-[:SIMILAR_TO {
  reason: "Shared dark woody oriental character",
  similarity_score: 0.81
}]->(f2);

// USER SIMILARITY — users with overlapping taste profiles
MATCH (u1:User {user_id: 1}), (u2:User {user_id: 4})
CREATE (u1)-[:SIMILAR_TASTE {
  reason: "Both Pakistani users rating fresh masculines highly",
  overlap_score: 0.68
}]->(u2);

MATCH (u1:User {user_id: 2}), (u2:User {user_id: 3})
CREATE (u1)-[:SIMILAR_TASTE {
  reason: "Both collectors gravitating toward dark woody orientals",
  overlap_score: 0.77
}]->(u2);