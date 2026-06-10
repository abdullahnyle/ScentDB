-- ScentDB: Fragrance Analytics Platform
-- PostgreSQL Schema

-- Brands Table
CREATE TABLE brands (
    brand_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    country VARCHAR(100),
    founded_year INT
);

-- Fragrances Table
CREATE TABLE fragrances (
    fragrance_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    brand_id INT REFERENCES brands(brand_id),
    concentration VARCHAR(50), -- EDP, EDT, Parfum
    release_year INT,
    price_usd DECIMAL(10,2),
    gender_target VARCHAR(20) -- Male, Female, Unisex
);

-- Users Table
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    age INT,
    country VARCHAR(100),
    joined_date DATE DEFAULT CURRENT_DATE
);

-- Purchases Table
CREATE TABLE purchases (
    purchase_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id),
    fragrance_id INT REFERENCES fragrances(fragrance_id),
    purchase_date DATE DEFAULT CURRENT_DATE,
    price_paid DECIMAL(10,2),
    bottle_size_ml INT
);

-- Ratings Table
CREATE TABLE ratings (
    rating_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id),
    fragrance_id INT REFERENCES fragrances(fragrance_id),
    score INT CHECK (score BETWEEN 1 AND 10),
    review_text TEXT,
    rated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);