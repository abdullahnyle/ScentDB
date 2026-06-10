// ScentDB: MongoDB Queries
// Run these in MongoDB Shell or MongoDB Compass

use("ScentDB");

// 1. Find all wear sessions for a specific user
db.wear_sessions.find({ user_id: 1 });

// 2. Find sessions where fragrance lasted more than 5 hours
db.wear_sessions.find({ duration_hours: { $gt: 5 } });

// 3. Average compliments received per fragrance
db.wear_sessions.aggregate([
  {
    $group: {
      _id: "$fragrance_name",
      avg_compliments: { $avg: "$compliments_received" },
      total_sessions: { $sum: 1 }
    }
  },
  { $sort: { avg_compliments: -1 } }
]);

// 4. Most popular occasions across all users
db.wear_sessions.aggregate([
  {
    $group: {
      _id: "$occasion",
      total_wears: { $sum: 1 },
      avg_duration: { $avg: "$duration_hours" }
    }
  },
  { $sort: { total_wears: -1 } }
]);

// 5. Find users who prefer EDP concentration
db.preference_logs.find({ preferred_concentration: "EDP" });

// 6. Find users with budget over $200 minimum
db.preference_logs.find({ "budget_range_usd.min": { $gte: 200 } });

// 7. Performance by weather condition
db.wear_sessions.aggregate([
  {
    $group: {
      _id: "$weather",
      avg_duration: { $avg: "$duration_hours" },
      avg_compliments: { $avg: "$compliments_received" },
      total_sessions: { $sum: 1 }
    }
  },
  { $sort: { avg_compliments: -1 } }
]);

// 8. Users with largest fragrance collections
db.preference_logs.find(
  {},
  { username: 1, current_collection_size: 1, _id: 0 }
).sort({ current_collection_size: -1 });