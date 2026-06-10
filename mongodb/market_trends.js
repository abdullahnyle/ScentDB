// ScentDB: Market Trends Collection
// =====================
// This collection exists because market trend data is fundamentally
// different from transactional data. Every region reports differently,
// every season has different attributes, and the schema evolves as
// we track new metrics. Forcing this into PostgreSQL would mean
// either nullable columns everywhere or a rigid schema that breaks
// every time the business wants to track something new.
// MongoDB handles this naturally — each document can carry exactly
// the fields that make sense for that region and time period.
// =====================

use("ScentDB");

db.market_trends.insertMany([

  // =====================
  // MIDDLE EAST
  // =====================
  {
    region: "Middle East",
    country: "UAE",
    period: "Q1-2024",
    season: "Winter",
    currency: "AED",
    market_size_usd_millions: 847,
    yoy_growth_percent: 12.4,
    top_selling_categories: [
      { category: "Oud-based", market_share_percent: 38 },
      { category: "Floral Oriental", market_share_percent: 24 },
      { category: "Fresh Citrus", market_share_percent: 18 },
      { category: "Woody", market_share_percent: 20 }
    ],
    consumer_demographics: {
      age_18_25: 22,
      age_26_35: 41,
      age_36_50: 28,
      age_50_plus: 9
    },
    avg_spend_per_customer_usd: 312,
    most_popular_fragrance_families: ["Oud", "Rose", "Musk"],
    seasonal_notes: "Winter drives the highest luxury fragrance sales in the UAE. Consumers gravitate toward heavier, warmer compositions. Oud remains culturally dominant year-round but peaks significantly in Q1.",
    emerging_trends: [
      "Niche European houses gaining traction among younger buyers",
      "Gender-neutral fragrances growing 18% YoY",
      "Local Emirati brands competing with European houses for the first time"
    ],
    top_retail_channels: {
      mall_boutiques: 45,
      online: 28,
      duty_free: 18,
      independent_retailers: 9
    },
    data_quality: "verified",
    source: "GCC Fragrance Industry Report 2024"
  },

  {
    region: "Middle East",
    country: "Saudi Arabia",
    period: "Q1-2024",
    season: "Winter",
    currency: "SAR",
    market_size_usd_millions: 1240,
    yoy_growth_percent: 15.7,
    top_selling_categories: [
      { category: "Oud-based", market_share_percent: 52 },
      { category: "Musky Oriental", market_share_percent: 21 },
      { category: "Floral", market_share_percent: 17 },
      { category: "Fresh", market_share_percent: 10 }
    ],
    consumer_demographics: {
      age_18_25: 31,
      age_26_35: 38,
      age_36_50: 22,
      age_50_plus: 9
    },
    avg_spend_per_customer_usd: 428,
    most_popular_fragrance_families: ["Oud", "Amber", "Musk", "Rose"],
    seasonal_notes: "Saudi Arabia is the largest fragrance market in the Middle East by volume. Oud is not just a preference here — it is deeply cultural. The 18-25 segment is the fastest growing, driven by social media influence and a young population.",
    emerging_trends: [
      "Social media influencers driving niche fragrance discovery",
      "Gifting culture pushing premium gift set sales up 24%",
      "International brands localizing their oud blends for Saudi taste profiles"
    ],
    top_retail_channels: {
      mall_boutiques: 51,
      online: 22,
      duty_free: 12,
      independent_retailers: 15
    },
    ramadan_effect: {
      sales_spike_percent: 34,
      top_gifting_fragrances: ["Oud Wood", "Black Orchid", "Aventus"],
      avg_gift_spend_usd: 185
    },
    data_quality: "verified",
    source: "GCC Fragrance Industry Report 2024"
  },

  // =====================
  // SOUTH ASIA
  // =====================
  {
    region: "South Asia",
    country: "Pakistan",
    period: "Q2-2024",
    season: "Summer",
    currency: "PKR",
    market_size_usd_millions: 156,
    yoy_growth_percent: 8.2,
    top_selling_categories: [
      { category: "Fresh Aquatic", market_share_percent: 31 },
      { category: "Citrus", market_share_percent: 27 },
      { category: "Oud-based", market_share_percent: 24 },
      { category: "Floral", market_share_percent: 18 }
    ],
    consumer_demographics: {
      age_18_25: 44,
      age_26_35: 33,
      age_36_50: 17,
      age_50_plus: 6
    },
    avg_spend_per_customer_usd: 48,
    most_popular_fragrance_families: ["Citrus", "Fresh", "Oud"],
    seasonal_notes: "Pakistani summers are extreme — temperatures regularly exceed 40°C in major cities. This drives a strong preference for fresh, light fragrances in Q2. The oud segment remains strong for evening and formal wear regardless of season.",
    emerging_trends: [
      "Western fragrance brands gaining popularity among urban youth",
      "Online fragrance communities growing rapidly on Instagram and TikTok",
      "Decant culture emerging in Lahore and Karachi as a way to try luxury scents affordably"
    ],
    climate_impact: {
      avg_summer_temp_celsius: 41,
      fragrance_longevity_reduction_percent: 35,
      consumer_preference_shift: "Consumers actively seek fresh and aquatic in summer; switch to heavier orientals in winter"
    },
    price_sensitivity: "high",
    luxury_segment_growth: 11.3,
    data_quality: "estimated",
    source: "Pakistan Retail Beauty Market Analysis 2024"
  },

  // =====================
  // WESTERN EUROPE
  // =====================
  {
    region: "Western Europe",
    country: "Ireland",
    period: "Q3-2024",
    season: "Autumn",
    currency: "EUR",
    market_size_usd_millions: 312,
    yoy_growth_percent: 5.1,
    top_selling_categories: [
      { category: "Fresh Fougere", market_share_percent: 29 },
      { category: "Woody Aromatic", market_share_percent: 26 },
      { category: "Floral", market_share_percent: 23 },
      { category: "Oriental", market_share_percent: 22 }
    ],
    consumer_demographics: {
      age_18_25: 19,
      age_26_35: 34,
      age_36_50: 31,
      age_50_plus: 16
    },
    avg_spend_per_customer_usd: 187,
    most_popular_fragrance_families: ["Woody", "Fresh", "Aromatic"],
    seasonal_notes: "Irish autumn and winter markets show strong preference for warm woody and aromatic compositions. The market is sophisticated — consumers research before buying and niche brands perform disproportionately well relative to population size.",
    emerging_trends: [
      "Sustainable and eco-certified fragrances growing 19% YoY",
      "Niche and artisan houses capturing 31% of premium segment",
      "Refillable fragrance bottles gaining mainstream acceptance"
    ],
    sustainability_metrics: {
      eco_certified_market_share: 14,
      refillable_packaging_growth_percent: 28,
      consumer_willingness_to_pay_premium_for_sustainability: 67
    },
    data_quality: "verified",
    source: "European Fragrance Federation Report 2024"
  },

  // =====================
  // NORTH AMERICA
  // =====================
  {
    region: "North America",
    country: "USA",
    period: "Q2-2024",
    season: "Summer",
    currency: "USD",
    market_size_usd_millions: 8420,
    yoy_growth_percent: 6.8,
    top_selling_categories: [
      { category: "Fresh Citrus", market_share_percent: 28 },
      { category: "Woody Musky", market_share_percent: 24 },
      { category: "Floral", market_share_percent: 22 },
      { category: "Oriental", market_share_percent: 16 },
      { category: "Gourmand", market_share_percent: 10 }
    ],
    consumer_demographics: {
      age_18_25: 26,
      age_26_35: 35,
      age_36_50: 27,
      age_50_plus: 12
    },
    avg_spend_per_customer_usd: 94,
    most_popular_fragrance_families: ["Fresh", "Woody", "Floral"],
    seasonal_notes: "The US market is the largest globally by revenue. Summer drives fresh and citrus sales heavily. The gourmand category (vanilla, caramel, sweet) is uniquely strong in North America compared to other regions.",
    emerging_trends: [
      "Celebrity fragrance collaborations driving mass market growth",
      "Gen Z preferring unique niche scents over designer staples",
      "Body mist and hair fragrance categories growing 31% YoY",
      "TikTok fragrance community influencing purchase decisions significantly"
    ],
    digital_influence: {
      purchases_influenced_by_social_media_percent: 54,
      tiktok_fragrance_hashtag_views_billions: 8.3,
      online_sales_share_percent: 38
    },
    data_quality: "verified",
    source: "NPD Group US Fragrance Market Report 2024"
  },

  // =====================
  // OCEANIA
  // =====================
  {
    region: "Oceania",
    country: "Australia",
    period: "Q4-2024",
    season: "Summer",
    currency: "AUD",
    market_size_usd_millions: 428,
    yoy_growth_percent: 7.3,
    top_selling_categories: [
      { category: "Fresh Aquatic", market_share_percent: 34 },
      { category: "Citrus Aromatic", market_share_percent: 28 },
      { category: "Floral", market_share_percent: 21 },
      { category: "Woody", market_share_percent: 17 }
    ],
    consumer_demographics: {
      age_18_25: 28,
      age_26_35: 36,
      age_36_50: 25,
      age_50_plus: 11
    },
    avg_spend_per_customer_usd: 112,
    most_popular_fragrance_families: ["Fresh", "Aquatic", "Citrus"],
    seasonal_notes: "Australian summer (Q4) strongly favors light, fresh, and aquatic compositions. The outdoor lifestyle culture directly shapes fragrance preferences — heavy orientals and ouds are niche rather than mainstream.",
    emerging_trends: [
      "Australian native botanical ingredients appearing in local fragrance brands",
      "Cruelty-free and vegan certifications becoming purchase decision factors",
      "International niche brands launching Australian-exclusive limited editions"
    ],
    climate_impact: {
      avg_summer_temp_celsius: 32,
      outdoor_lifestyle_index: "high",
      preference_note: "Outdoor culture drives preference for subtle, fresh scents that do not overwhelm in open-air settings"
    },
    data_quality: "verified",
    source: "IBIS World Australian Cosmetics Report 2024"
  }

]);

// =====================
// USEFUL MARKET TREND QUERIES
// =====================

// Which region has the highest average spend per customer?
db.market_trends.aggregate([
  {
    $group: {
      _id: "$region",
      avg_spend: { $avg: "$avg_spend_per_customer_usd" },
      total_market_size: { $sum: "$market_size_usd_millions" }
    }
  },
  { $sort: { avg_spend: -1 } }
]);

// Which markets are growing fastest?
db.market_trends.find(
  { yoy_growth_percent: { $gte: 10 } },
  { country: 1, region: 1, yoy_growth_percent: 1, _id: 0 }
).sort({ yoy_growth_percent: -1 });

// Find all markets where oud is a top selling category
db.market_trends.find({
  "top_selling_categories.category": { $regex: "Oud", $options: "i" }
},
{ country: 1, region: 1, "top_selling_categories.$": 1, _id: 0 });

// Average market size by region
db.market_trends.aggregate([
  {
    $group: {
      _id: "$region",
      avg_market_size_usd_millions: { $avg: "$market_size_usd_millions" },
      countries_tracked: { $sum: 1 }
    }
  },
  { $sort: { avg_market_size_usd_millions: -1 } }
]);

// Which markets have verified data quality?
db.market_trends.find(
  { data_quality: "verified" },
  { country: 1, region: 1, period: 1, _id: 0 }
);