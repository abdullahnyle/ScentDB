// ScentDB: MongoDB Documents
// These represent variable behavioral data - wear sessions and preference logs
// Run these in MongoDB Shell or MongoDB Compass

// Switch to ScentDB database
use("ScentDB");

// =====================
// WEAR SESSIONS
// =====================
// Variable structure per entry - perfect use case for MongoDB

db.wear_sessions.insertMany([
  {
    user_id: 1,
    username: "scentlover1",
    fragrance_id: 1,
    fragrance_name: "Aventus",
    date: "2024-06-01",
    occasion: "Wedding",
    mood: "Confident",
    weather: "Hot",
    temperature_celsius: 38,
    duration_hours: 6,
    compliments_received: 4,
    notes: "Incredible performance in the heat. Got so many compliments.",
    extra_data: {
      outfit_color: "Navy",
      location: "Lahore",
      reapplied: false
    }
  },
  {
    user_id: 1,
    username: "scentlover1",
    fragrance_id: 2,
    fragrance_name: "Sauvage",
    date: "2024-06-05",
    occasion: "Office",
    mood: "Focused",
    weather: "Mild",
    temperature_celsius: 28,
    duration_hours: 8,
    compliments_received: 2,
    notes: "Safe and inoffensive for office environment."
  },
  {
    user_id: 2,
    username: "fragrancepro",
    fragrance_id: 3,
    fragrance_name: "Oud Wood",
    date: "2024-06-03",
    occasion: "Date Night",
    mood: "Romantic",
    weather: "Cool",
    temperature_celsius: 22,
    duration_hours: 7,
    compliments_received: 5,
    notes: "Perfect for evenings. Very intimate and warm.",
    extra_data: {
      outfit_color: "Black",
      location: "Dubai",
      reapplied: true,
      reapply_after_hours: 5
    }
  },
  {
    user_id: 3,
    username: "oud_addict",
    fragrance_id: 5,
    fragrance_name: "Bleu de Chanel",
    date: "2024-06-07",
    occasion: "Casual",
    mood: "Relaxed",
    weather: "Rainy",
    temperature_celsius: 15,
    duration_hours: 5,
    compliments_received: 1,
    notes: "Performs differently in cold weather. More subtle."
  },
  {
    user_id: 4,
    username: "perfume_pk",
    fragrance_id: 4,
    fragrance_name: "Eros",
    date: "2024-06-10",
    occasion: "Gym",
    mood: "Energetic",
    weather: "Hot",
    temperature_celsius: 35,
    duration_hours: 2,
    compliments_received: 0,
    notes: "Faded quickly at the gym. Not ideal for sport.",
    extra_data: {
      workout_type: "Weightlifting",
      location: "Lahore"
    }
  }
]);

// =====================
// PREFERENCE LOGS
// =====================
// Tracks evolving user taste profiles over time

db.preference_logs.insertMany([
  {
    user_id: 1,
    username: "scentlover1",
    logged_at: "2024-06-01",
    favorite_notes: ["Bergamot", "Oakmoss", "Ambergris"],
    disliked_notes: ["Patchouli", "Vanilla"],
    preferred_occasions: ["Wedding", "Evening"],
    preferred_concentration: "EDP",
    budget_range_usd: {
      min: 200,
      max: 600
    },
    current_collection_size: 8
  },
  {
    user_id: 2,
    username: "fragrancepro",
    logged_at: "2024-06-03",
    favorite_notes: ["Oud", "Sandalwood", "Rose"],
    disliked_notes: ["Citrus", "Aquatic"],
    preferred_occasions: ["Date Night", "Formal"],
    preferred_concentration: "EDP",
    budget_range_usd: {
      min: 150,
      max: 400
    },
    current_collection_size: 15,
    extra_data: {
      certified_reviewer: true,
      fragrance_blog: "www.fragrancepro.com"
    }
  },
  {
    user_id: 3,
    username: "oud_addict",
    logged_at: "2024-06-07",
    favorite_notes: ["Oud", "Leather", "Tobacco"],
    disliked_notes: ["Floral", "Sweet"],
    preferred_occasions: ["Casual", "Evening"],
    preferred_concentration: "Parfum",
    budget_range_usd: {
      min: 100,
      max: 300
    },
    current_collection_size: 22
  }
]);