// ScentDB: Advanced Aggregation Pipelines
// =====================
// If the basic queries in queries.js are the equivalent of
// SELECT statements, these pipelines are the equivalent of
// the complex multi-CTE analytical queries we built in the
// PostgreSQL analytics folder. MongoDB's aggregation framework
// is genuinely powerful — it can reshape, enrich, bucket,
// and summarize data in ways that go well beyond simple filtering.
//
// The pipelines here solve real business problems using the
// behavioral data that lives in MongoDB — the wear sessions,
// preference logs, and market trends that do not fit neatly
// into the relational model. Each one is annotated with
// what business question it answers and why MongoDB is the
// right tool for that specific question.
//
// For a portfolio this file demonstrates something specific:
// that you understand not just how to query a database but
// why different data lives in different systems and how to
// extract value from each one on its own terms.
// =====================

use("ScentDB");

// =====================
// PIPELINE 1: FRAGRANCE PERFORMANCE BY WEATHER
// =====================
// Which fragrances perform best in which weather conditions?
// This question cannot be answered from PostgreSQL alone
// because weather data lives in the wear_sessions collection.
// The answer shapes everything from seasonal marketing
// to which fragrances to feature on hot days vs cold ones.

db.wear_sessions.aggregate([
    // Stage 1: Group by fragrance and weather condition
    {
        $group: {
            _id: {
                fragrance: "$fragrance_name",
                weather: "$weather"
            },
            total_sessions: { $sum: 1 },
            avg_duration: { $avg: "$duration_hours" },
            avg_compliments: { $avg: "$compliments_received" },
            total_compliments: { $sum: "$compliments_received" },
            avg_temperature: { $avg: "$temperature_celsius" }
        }
    },
    // Stage 2: Calculate a performance score for each combination
    {
        $addFields: {
            performance_score: {
                $round: [
                    {
                        $add: [
                            { $multiply: ["$avg_compliments", 0.5] },
                            { $multiply: ["$avg_duration", 0.3] },
                            { $multiply: ["$total_sessions", 0.2] }
                        ]
                    },
                    2
                ]
            }
        }
    },
    // Stage 3: Sort by performance score descending
    { $sort: { performance_score: -1 } },
    // Stage 4: Clean up the output shape
    {
        $project: {
            _id: 0,
            fragrance: "$_id.fragrance",
            weather_condition: "$_id.weather",
            total_sessions: 1,
            avg_duration_hours: { $round: ["$avg_duration", 1] },
            avg_compliments: { $round: ["$avg_compliments", 1] },
            avg_temperature_celsius: { $round: ["$avg_temperature", 1] },
            performance_score: 1
        }
    }
]);

// =====================
// PIPELINE 2: USER TASTE PROFILE BUILDER
// =====================
// This pipeline constructs a complete taste profile for each user
// by combining their wear session behavior with their stated
// preferences from the preference_logs collection.
// The output feeds directly into the recommendation engine —
// a richer profile means better recommendations.
// This kind of enrichment pipeline is exactly what data
// engineering teams build to feed ML models downstream.

db.wear_sessions.aggregate([
    // Stage 1: Calculate behavioral signals per user
    {
        $group: {
            _id: "$user_id",
            username: { $first: "$username" },
            total_wear_sessions: { $sum: 1 },
            avg_session_duration: { $avg: "$duration_hours" },
            total_compliments: { $sum: "$compliments_received" },
            avg_compliments_per_wear: { $avg: "$compliments_received" },
            occasions_list: { $push: "$occasion" },
            fragrances_worn: { $addToSet: "$fragrance_name" },
            weather_worn_in: { $addToSet: "$weather" },
            moods_during_wear: { $addToSet: "$mood" }
        }
    },
    // Stage 2: Join with preference logs
    {
        $lookup: {
            from: "preference_logs",
            localField: "_id",
            foreignField: "user_id",
            as: "preferences"
        }
    },
    // Stage 3: Flatten the preferences array (one doc per user)
    {
        $unwind: {
            path: "$preferences",
            preserveNullAndEmptyArrays: true
        }
    },
    // Stage 4: Build the unified profile document
    {
        $project: {
            _id: 0,
            user_id: "$_id",
            username: 1,
            behavioral_data: {
                total_wear_sessions: "$total_wear_sessions",
                avg_session_duration_hours: {
                    $round: ["$avg_session_duration", 1]
                },
                avg_compliments_per_wear: {
                    $round: ["$avg_compliments_per_wear", 1]
                },
                fragrances_worn: "$fragrances_worn",
                occasions: "$occasions_list",
                active_in_weather: "$weather_worn_in",
                moods_during_wear: "$moods_during_wear"
            },
            stated_preferences: {
                favorite_notes: "$preferences.favorite_notes",
                disliked_notes: "$preferences.disliked_notes",
                preferred_occasions: "$preferences.preferred_occasions",
                preferred_concentration: "$preferences.preferred_concentration",
                budget_range: "$preferences.budget_range_usd",
                collection_size: "$preferences.current_collection_size"
            },
            profile_completeness: {
                $cond: {
                    if: { $gt: ["$preferences", null] },
                    then: "Full profile — behavioral + stated preferences",
                    else: "Partial profile — behavioral data only"
                }
            }
        }
    },
    { $sort: { "behavioral_data.total_wear_sessions": -1 } }
]);

// =====================
// PIPELINE 3: MARKET TREND CROSS ANALYSIS
// =====================
// This pipeline analyzes the market_trends collection to find
// patterns across regions — which markets are growing fastest,
// where spending is highest, and where emerging trends are
// consistent enough to act on.
// The output would feed a regional strategy presentation —
// the kind of document a business analyst prepares for a
// commercial leadership team before they decide where to
// invest marketing budget next quarter.

db.market_trends.aggregate([
    // Stage 1: Unwind the top selling categories array
    // so each category gets its own document for analysis
    { $unwind: "$top_selling_categories" },
    // Stage 2: Group by region and category
    {
        $group: {
            _id: {
                region: "$region",
                category: "$top_selling_categories.category"
            },
            avg_market_share: {
                $avg: "$top_selling_categories.market_share_percent"
            },
            total_market_size: { $sum: "$market_size_usd_millions" },
            avg_growth_rate: { $avg: "$yoy_growth_percent" },
            avg_consumer_spend: { $avg: "$avg_spend_per_customer_usd" },
            countries_in_region: { $addToSet: "$country" }
        }
    },
    // Stage 3: Add a market opportunity score
    {
        $addFields: {
            opportunity_score: {
                $round: [
                    {
                        $add: [
                            {
                                $multiply: [
                                    "$avg_growth_rate", 0.40
                                ]
                            },
                            {
                                $multiply: [
                                    { $divide: ["$avg_consumer_spend", 10] },
                                    0.35
                                ]
                            },
                            {
                                $multiply: [
                                    "$avg_market_share", 0.25
                                ]
                            }
                        ]
                    },
                    2
                ]
            }
        }
    },
    // Stage 4: Sort by opportunity score
    { $sort: { opportunity_score: -1 } },
    // Stage 5: Clean output
    {
        $project: {
            _id: 0,
            region: "$_id.region",
            fragrance_category: "$_id.category",
            avg_market_share_percent: {
                $round: ["$avg_market_share", 1]
            },
            total_market_size_usd_millions: "$total_market_size",
            avg_yoy_growth_percent: {
                $round: ["$avg_growth_rate", 1]
            },
            avg_consumer_spend_usd: {
                $round: ["$avg_consumer_spend", 0]
            },
            countries: "$countries_in_region",
            opportunity_score: 1
        }
    }
]);

// =====================
// PIPELINE 4: WEAR SESSION TIME SERIES ANALYSIS
// =====================
// How does fragrance wearing behavior change over time?
// Are people wearing fragrances more or less frequently
// month on month? Are session durations trending up or down?
// Time series analysis on behavioral data is one of the
// most common requests a product analytics team gets.
// This pipeline builds it from the raw wear session documents.

db.wear_sessions.aggregate([
    // Stage 1: Extract year and month from the date string
    {
        $addFields: {
            year_month: {
                $substr: ["$date", 0, 7]
            }
        }
    },
    // Stage 2: Group by month
    {
        $group: {
            _id: "$year_month",
            total_sessions: { $sum: 1 },
            unique_users: { $addToSet: "$user_id" },
            unique_fragrances: { $addToSet: "$fragrance_name" },
            avg_duration: { $avg: "$duration_hours" },
            total_compliments: { $sum: "$compliments_received" },
            occasions: { $push: "$occasion" },
            weather_conditions: { $push: "$weather" }
        }
    },
    // Stage 3: Calculate derived metrics
    {
        $addFields: {
            unique_user_count: { $size: "$unique_users" },
            unique_fragrance_count: { $size: "$unique_fragrances" },
            avg_compliments_per_session: {
                $divide: ["$total_compliments", "$total_sessions"]
            }
        }
    },
    // Stage 4: Sort chronologically
    { $sort: { _id: 1 } },
    // Stage 5: Final output shape
    {
        $project: {
            _id: 0,
            month: "$_id",
            total_sessions: 1,
            unique_users: "$unique_user_count",
            unique_fragrances_worn: "$unique_fragrance_count",
            avg_session_duration_hours: {
                $round: ["$avg_duration", 1]
            },
            avg_compliments_per_session: {
                $round: ["$avg_compliments_per_session", 1]
            },
            total_compliments_received: "$total_compliments"
        }
    }
]);

// =====================
// PIPELINE 5: OCCASION INTELLIGENCE
// =====================
// Different occasions call for different fragrances and
// different fragrances perform differently depending on
// the occasion they are worn to. This pipeline builds
// an occasion-level intelligence report — which occasions
// drive the most wear sessions, which ones produce the
// most compliments, and which fragrances dominate each one.
// A fragrance retailer would use this to build occasion-based
// collections and targeted recommendation flows.

db.wear_sessions.aggregate([
    // Stage 1: Group by occasion
    {
        $group: {
            _id: "$occasion",
            total_sessions: { $sum: 1 },
            unique_users: { $addToSet: "$user_id" },
            fragrances_worn: { $addToSet: "$fragrance_name" },
            avg_duration: { $avg: "$duration_hours" },
            avg_compliments: { $avg: "$compliments_received" },
            total_compliments: { $sum: "$compliments_received" },
            weather_breakdown: { $push: "$weather" },
            mood_breakdown: { $push: "$mood" }
        }
    },
    // Stage 2: Add derived fields
    {
        $addFields: {
            unique_user_count: { $size: "$unique_users" },
            fragrance_variety: { $size: "$fragrances_worn" },
            compliments_per_session: {
                $round: [
                    { $divide: ["$total_compliments", "$total_sessions"] },
                    2
                ]
            }
        }
    },
    // Stage 3: Sort by total sessions
    { $sort: { total_sessions: -1 } },
    // Stage 4: Project clean output
    {
        $project: {
            _id: 0,
            occasion: "$_id",
            total_sessions: 1,
            unique_users: "$unique_user_count",
            fragrance_variety: 1,
            fragrances_worn: 1,
            avg_duration_hours: { $round: ["$avg_duration", 1] },
            avg_compliments: { $round: ["$avg_compliments", 1] },
            compliments_per_session: 1,
            total_compliments: 1
        }
    }
]);

// =====================
// PIPELINE 6: PREFERENCE TO BEHAVIOR GAP ANALYSIS
// =====================
// One of the most interesting questions in consumer analytics
// is the gap between what people say they like and what they
// actually do. Someone might list Oud as their favorite note
// but their wear sessions show they mostly reach for fresh
// citrus fragrances. That gap is not a data error — it is
// a genuine behavioral insight. People aspire to one thing
// and habitually do another. Understanding that gap helps
// build recommendations that meet users where they actually
// are rather than where they think they are.

db.preference_logs.aggregate([
    // Stage 1: Join with wear sessions to compare stated vs actual
    {
        $lookup: {
            from: "wear_sessions",
            localField: "user_id",
            foreignField: "user_id",
            as: "actual_wear_sessions"
        }
    },
    // Stage 2: Unwind sessions for analysis
    {
        $unwind: {
            path: "$actual_wear_sessions",
            preserveNullAndEmptyArrays: true
        }
    },
    // Stage 3: Group back by user with both dimensions
    {
        $group: {
            _id: "$user_id",
            username: { $first: "$username" },
            stated_favorites: { $first: "$favorite_notes" },
            stated_dislikes: { $first: "$disliked_notes" },
            stated_occasions: { $first: "$preferred_occasions" },
            actual_fragrances_worn: {
                $addToSet: "$actual_wear_sessions.fragrance_name"
            },
            actual_occasions: {
                $addToSet: "$actual_wear_sessions.occasion"
            },
            actual_avg_duration: {
                $avg: "$actual_wear_sessions.duration_hours"
            },
            actual_total_sessions: { $sum: 1 }
        }
    },
    // Stage 4: Build the gap analysis document
    {
        $project: {
            _id: 0,
            user_id: "$_id",
            username: 1,
            stated_favorite_notes: "$stated_favorites",
            stated_disliked_notes: "$stated_dislikes",
            stated_preferred_occasions: "$stated_occasions",
            actual_fragrances_worn: 1,
            actual_occasions_observed: "$actual_occasions",
            actual_avg_session_duration: {
                $round: ["$actual_avg_duration", 1]
            },
            total_observed_sessions: "$actual_total_sessions",
            analysis_note: {
                $cond: {
                    if: { $gt: ["$actual_total_sessions", 2] },
                    then: "Sufficient behavioral data for gap analysis",
                    else: "Limited sessions — stated preferences weighted higher"
                }
            }
        }
    },
    { $sort: { total_observed_sessions: -1 } }
]);

// =====================
// PIPELINE 7: EMERGING TREND SIGNAL DETECTOR
// =====================
// The market_trends collection contains emerging_trends arrays
// for each country and region. This pipeline extracts those
// signals, normalises them across markets, and surfaces the
// trends that appear most consistently — the ones worth
// actually acting on versus the ones that are noise in
// a single market.

db.market_trends.aggregate([
    // Stage 1: Unwind the emerging trends array
    { $unwind: "$emerging_trends" },
    // Stage 2: Group by trend text to find cross market patterns
    {
        $group: {
            _id: "$emerging_trends",
            markets_reporting: { $addToSet: "$country" },
            regions_reporting: { $addToSet: "$region" },
            total_mentions: { $sum: 1 },
            avg_growth_in_markets: { $avg: "$yoy_growth_percent" },
            avg_market_size: { $avg: "$market_size_usd_millions" }
        }
    },
    // Stage 3: Score the signal strength
    {
        $addFields: {
            market_count: { $size: "$markets_reporting" },
            region_count: { $size: "$regions_reporting" },
            signal_strength: {
                $round: [
                    {
                        $multiply: [
                            { $size: "$markets_reporting" },
                            "$avg_growth_in_markets"
                        ]
                    },
                    1
                ]
            }
        }
    },
    // Stage 4: Filter to trends appearing in more than one market
    {
        $match: {
            market_count: { $gte: 1 }
        }
    },
    // Stage 5: Sort by signal strength
    { $sort: { signal_strength: -1, market_count: -1 } },
    // Stage 6: Final output
    {
        $project: {
            _id: 0,
            trend: "$_id",
            markets_reporting: 1,
            regions_reporting: 1,
            total_mentions: 1,
            market_count: 1,
            avg_growth_in_reporting_markets: {
                $round: ["$avg_growth_in_markets", 1]
            },
            signal_strength: 1,
            recommendation: {
                $cond: {
                    if: { $gte: ["$market_count", 3] },
                    then: "Global signal — act now",
                    else: {
                        $cond: {
                            if: { $gte: ["$market_count", 2] },
                            then: "Regional signal — monitor closely",
                            else: "Single market signal — watch but do not commit"
                        }
                    }
                }
            }
        }
    }
]);