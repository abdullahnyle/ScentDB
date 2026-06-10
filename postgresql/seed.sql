-- ScentDB: Seed Data

-- Brands
INSERT INTO brands (name, country, founded_year) VALUES
('Creed', 'France', 1760),
('Dior', 'France', 1946),
('Tom Ford', 'USA', 2005),
('Versace', 'Italy', 1978),
('Chanel', 'France', 1910);

-- Fragrances
INSERT INTO fragrances (name, brand_id, concentration, release_year, price_usd, gender_target) VALUES
('Aventus', 1, 'EDP', 2010, 495.00, 'Male'),
('Sauvage', 2, 'EDT', 2015, 120.00, 'Male'),
('Oud Wood', 3, 'EDP', 2007, 310.00, 'Unisex'),
('Eros', 4, 'EDT', 2012, 95.00, 'Male'),
('Bleu de Chanel', 5, 'EDP', 2010, 185.00, 'Male'),
('Miss Dior', 2, 'EDP', 2011, 140.00, 'Female'),
('Black Orchid', 3, 'EDP', 2006, 290.00, 'Unisex'),
('Allure Homme', 5, 'EDT', 1999, 110.00, 'Male');

-- Users
INSERT INTO users (username, email, age, country) VALUES
('scentlover1', 'ali@email.com', 24, 'Pakistan'),
('fragrancepro', 'sara@email.com', 28, 'UAE'),
('oud_addict', 'james@email.com', 31, 'UK'),
('perfume_pk', 'ahmed@email.com', 22, 'Pakistan'),
('scentseeker', 'emma@email.com', 26, 'Ireland');

-- Purchases
INSERT INTO purchases (user_id, fragrance_id, purchase_date, price_paid, bottle_size_ml) VALUES
(1, 1, '2024-01-15', 495.00, 100),
(1, 2, '2024-03-22', 120.00, 100),
(2, 3, '2024-02-10', 310.00, 50),
(3, 5, '2024-04-05', 185.00, 100),
(4, 4, '2024-01-30', 95.00, 50),
(5, 7, '2024-05-12', 290.00, 100),
(2, 8, '2024-03-18', 110.00, 75),
(4, 2, '2024-06-01', 120.00, 50);

-- Ratings
INSERT INTO ratings (user_id, fragrance_id, score, review_text) VALUES
(1, 1, 9, 'Incredible projection and longevity. Worth every penny.'),
(1, 2, 8, 'Fresh and powerful. Great for daily wear.'),
(2, 3, 10, 'Best oud fragrance I have ever tried. Absolutely stunning.'),
(3, 5, 9, 'Sophisticated and versatile. My signature scent.'),
(4, 4, 7, 'Good for the price. Longevity could be better.'),
(5, 7, 8, 'Dark and mysterious. Love wearing it in winter.'),
(2, 8, 7, 'Classic and clean. A safe choice for office wear.'),
(4, 2, 9, 'Amazing performance. Gets compliments every time.');