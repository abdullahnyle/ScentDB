// ScentDB: MongoDB Schema Validation
// =====================
// One of the most common criticisms of MongoDB is that it is
// schemaless — you can insert anything into any collection
// and the database will happily accept it. That flexibility
// is genuinely useful when your data structure is evolving
// or when different documents in the same collection need
// different fields. But it also means bad data gets in easily
// if you are not deliberate about validation.
//
// MongoDB's schema validation feature lets you define rules
// that every document must satisfy before it is accepted.
// It is not as strict as PostgreSQL's type system and
// constraints — you can still have optional fields and
// variable structure — but it catches the obvious mistakes:
// a wear session with no user ID, a preference log with a
// budget range that is somehow negative, a market trend
// document missing the region it belongs to.
//
// For a portfolio this file demonstrates something that most
// MongoDB tutorials skip entirely: that you think about data
// quality in NoSQL the same way you think about it in SQL.
// The tools are different but the discipline is the same.
// Data that enters the system clean stays clean.
// Data that enters dirty contaminates everything downstream.
// =====================

use("ScentDB");

// =====================
// WEAR SESSIONS VALIDATION
// =====================
// Every wear session must have a user, a fragrance, a date,
// and an occasion. Everything else is optional because
// the whole point of storing this in MongoDB is to allow
// variable structure — some sessions have weather data,
// some have outfit notes, some have neither. The required
// fields are the minimum that makes a document useful.

db.runCommand({
    collMod: "wear_sessions",
    validator: {
        $jsonSchema: {
            bsonType: "object",
            title: "Wear Session Validation",
            description: "Every wear session must have a user, fragrance, date, and occasion at minimum",
            required: [
                "user_id",
                "username",
                "fragrance_id",
                "fragrance_name",
                "date",
                "occasion"
            ],
            properties: {
                user_id: {
                    bsonType: "int",
                    minimum: 1,
                    description: "Must be a positive integer matching a user in PostgreSQL"
                },
                username: {
                    bsonType: "string",
                    minLength: 1,
                    maxLength: 100,
                    description: "Must be a non-empty string"
                },
                fragrance_id: {
                    bsonType: "int",
                    minimum: 1,
                    description: "Must be a positive integer matching a fragrance in PostgreSQL"
                },
                fragrance_name: {
                    bsonType: "string",
                    minLength: 1,
                    description: "Must be a non-empty string"
                },
                date: {
                    bsonType: "string",
                    pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
                    description: "Must be a valid date string in YYYY-MM-DD format"
                },
                occasion: {
                    bsonType: "string",
                    enum: [
                        "Wedding",
                        "Office",
                        "Date Night",
                        "Casual",
                        "Gym",
                        "Formal",
                        "Evening",
                        "Travel",
                        "Outdoor",
                        "Special Event"
                    ],
                    description: "Must be one of the approved occasion types"
                },
                mood: {
                    bsonType: "string",
                    description: "Optional — how the user felt while wearing it"
                },
                weather: {
                    bsonType: "string",
                    enum: ["Hot", "Warm", "Mild", "Cool", "Cold", "Rainy", "Humid"],
                    description: "Optional — must be a recognized weather condition if provided"
                },
                temperature_celsius: {
                    bsonType: "int",
                    minimum: -20,
                    maximum: 55,
                    description: "Optional — must be a realistic temperature if provided"
                },
                duration_hours: {
                    bsonType: ["int", "double"],
                    minimum: 0,
                    maximum: 24,
                    description: "Optional — hours worn, must be between 0 and 24"
                },
                compliments_received: {
                    bsonType: "int",
                    minimum: 0,
                    maximum: 50,
                    description: "Optional — must be a non-negative integer if provided"
                },
                notes: {
                    bsonType: "string",
                    maxLength: 1000,
                    description: "Optional — free text notes, max 1000 characters"
                },
                extra_data: {
                    bsonType: "object",
                    description: "Optional — any additional variable fields go here"
                }
            },
            // Disallow extra top-level fields we did not define
            // This prevents schema drift where random fields
            // accumulate over time and nobody knows what they mean
            additionalProperties: true
        }
    },
    // WARN logs a warning but still accepts the document
    // ERROR rejects the document entirely
    // Start with WARN in development, switch to ERROR in production
    validationLevel: "moderate",
    validationAction: "warn"
});

// =====================
// PREFERENCE LOGS VALIDATION
// =====================
// Preference logs are more structured than wear sessions
// because they represent deliberate user input rather than
// behavioral observation. A user sat down and told the system
// what they like. That intentionality means we can be stricter
// about what we accept.

db.runCommand({
    collMod: "preference_logs",
    validator: {
        $jsonSchema: {
            bsonType: "object",
            title: "Preference Log Validation",
            description: "User preference logs must have user identity and at least one preference dimension",
            required: [
                "user_id",
                "username",
                "logged_at"
            ],
            properties: {
                user_id: {
                    bsonType: "int",
                    minimum: 1,
                    description: "Must be a positive integer"
                },
                username: {
                    bsonType: "string",
                    minLength: 1,
                    description: "Must be a non-empty string"
                },
                logged_at: {
                    bsonType: "string",
                    pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
                    description: "Must be a valid date string in YYYY-MM-DD format"
                },
                favorite_notes: {
                    bsonType: "array",
                    items: {
                        bsonType: "string",
                        minLength: 1
                    },
                    description: "Optional — array of note name strings"
                },
                disliked_notes: {
                    bsonType: "array",
                    items: {
                        bsonType: "string",
                        minLength: 1
                    },
                    description: "Optional — array of note name strings"
                },
                preferred_occasions: {
                    bsonType: "array",
                    items: {
                        bsonType: "string"
                    },
                    description: "Optional — array of occasion strings"
                },
                preferred_concentration: {
                    bsonType: "string",
                    enum: ["EDT", "EDP", "Parfum", "EDC", "Solid"],
                    description: "Optional — must be a recognized concentration type"
                },
                budget_range_usd: {
                    bsonType: "object",
                    required: ["min", "max"],
                    properties: {
                        min: {
                            bsonType: ["int", "double"],
                            minimum: 0,
                            description: "Minimum budget must be non-negative"
                        },
                        max: {
                            bsonType: ["int", "double"],
                            minimum: 0,
                            description: "Maximum budget must be non-negative"
                        }
                    },
                    description: "Optional — if provided must have both min and max"
                },
                current_collection_size: {
                    bsonType: "int",
                    minimum: 0,
                    maximum: 10000,
                    description: "Optional — number of fragrances owned, must be realistic"
                },
                extra_data: {
                    bsonType: "object",
                    description: "Optional — any additional variable fields"
                }
            }
        }
    },
    validationLevel: "moderate",
    validationAction: "warn"
});

// =====================
// MARKET TRENDS VALIDATION
// =====================
// Market trend documents come from external research sources
// and get loaded in bulk. Without validation a malformed
// import could bring in documents missing the region or
// country fields that every downstream query depends on.
// Strict validation here protects the analytics layer.

db.runCommand({
    collMod: "market_trends",
    validator: {
        $jsonSchema: {
            bsonType: "object",
            title: "Market Trend Validation",
            description: "Market trend documents must identify their region and time period",
            required: [
                "region",
                "country",
                "period",
                "market_size_usd_millions",
                "yoy_growth_percent"
            ],
            properties: {
                region: {
                    bsonType: "string",
                    enum: [
                        "Middle East",
                        "South Asia",
                        "Western Europe",
                        "Eastern Europe",
                        "North America",
                        "South America",
                        "Oceania",
                        "East Asia",
                        "Southeast Asia",
                        "Africa"
                    ],
                    description: "Must be a recognized world region"
                },
                country: {
                    bsonType: "string",
                    minLength: 2,
                    description: "Must be a non-empty country name"
                },
                period: {
                    bsonType: "string",
                    pattern: "^Q[1-4]-[0-9]{4}$",
                    description: "Must be in Q1-2024 format"
                },
                market_size_usd_millions: {
                    bsonType: ["int", "double"],
                    minimum: 0,
                    description: "Must be a non-negative number"
                },
                yoy_growth_percent: {
                    bsonType: ["int", "double"],
                    minimum: -100,
                    maximum: 200,
                    description: "Year on year growth as a percentage, must be realistic"
                },
                avg_spend_per_customer_usd: {
                    bsonType: ["int", "double"],
                    minimum: 0,
                    description: "Optional — must be non-negative if provided"
                },
                top_selling_categories: {
                    bsonType: "array",
                    items: {
                        bsonType: "object",
                        required: ["category", "market_share_percent"],
                        properties: {
                            category: {
                                bsonType: "string",
                                minLength: 1
                            },
                            market_share_percent: {
                                bsonType: ["int", "double"],
                                minimum: 0,
                                maximum: 100
                            }
                        }
                    },
                    description: "Optional — each category needs a name and market share"
                },
                data_quality: {
                    bsonType: "string",
                    enum: ["verified", "estimated", "preliminary", "unverified"],
                    description: "Optional — must be a recognized quality classification"
                },
                source: {
                    bsonType: "string",
                    description: "Optional — but strongly recommended for data lineage"
                }
            }
        }
    },
    validationLevel: "moderate",
    validationAction: "warn"
});

// =====================
// TESTING THE VALIDATION RULES
// =====================
// These inserts test whether the validation is working.
// The first group should be accepted.
// The second group should trigger warnings because they
// violate the schema rules we just defined.

// Valid document — should pass
db.wear_sessions.insertOne({
    user_id: 1,
    username: "scentlover1",
    fragrance_id: 1,
    fragrance_name: "Aventus",
    date: "2024-07-01",
    occasion: "Wedding",
    mood: "Confident",
    weather: "Hot",
    temperature_celsius: 38,
    duration_hours: 6,
    compliments_received: 3,
    notes: "Performed exceptionally well in the heat."
});

// Invalid document — missing required occasion field
// Should trigger a validation warning
db.wear_sessions.insertOne({
    user_id: 1,
    username: "scentlover1",
    fragrance_id: 2,
    fragrance_name: "Sauvage",
    date: "2024-07-02"
    // occasion is missing — this violates the required fields rule
});

// Invalid document — temperature out of realistic range
// Should trigger a validation warning
db.wear_sessions.insertOne({
    user_id: 2,
    username: "fragrancepro",
    fragrance_id: 3,
    fragrance_name: "Oud Wood",
    date: "2024-07-03",
    occasion: "Evening",
    temperature_celsius: 200  // nobody is wearing fragrance at 200 degrees
});

// Invalid market trend — wrong period format
// Should trigger a validation warning
db.market_trends.insertOne({
    region: "Middle East",
    country: "Kuwait",
    period: "July 2024",  // should be Q3-2024 format
    market_size_usd_millions: 245,
    yoy_growth_percent: 9.1
});

// =====================
// VIEWING VALIDATION RULES
// =====================
// Check what validation rules are currently active
// on each collection in the database.

db.getCollectionInfos().forEach(collection => {
    if (collection.options && collection.options.validator) {
        print("Collection: " + collection.name);
        print("Validation Level: " + collection.options.validationLevel);
        print("Validation Action: " + collection.options.validationAction);
        printjson(collection.options.validator);
        print("---");
    }
});

// =====================
// REMOVING VALIDATION
// =====================
// If validation is causing problems during development
// you can temporarily disable it without dropping the collection.
// Never do this in production without a plan to re-enable it.

// db.runCommand({
//     collMod: "wear_sessions",
//     validationLevel: "off"
// });

// Re-enable with:
// db.runCommand({
//     collMod: "wear_sessions",
//     validationLevel: "moderate",
//     validationAction: "warn"
// });