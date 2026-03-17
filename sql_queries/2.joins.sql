-- ================
-- 1. SETTING PRIMARIES AND FOREIGN KEYS
-- ================
## Before performing joins we check each table and set the keys


-- Table apps_description
DESCRIBE apps_description; -- everything is already set for the keys

ALTER TABLE apps_description
CHANGE id app_id VARCHAR(100); -- Changing apps id name


-- Table pricing_plans2
DESCRIBE pricing_plans2;

ALTER TABLE pricing_plans2
CHANGE id pricing_id VARCHAR(100),
CHANGE app_id app_id VARCHAR(100),
ADD FOREIGN KEY(app_id)
REFERENCES apps_description(app_id);

-- Table reviews_edited
DESCRIBE reviews_edited;

ALTER TABLE reviews_edited
ADD CONSTRAINT fk_review_app
FOREIGN KEY(app_id)
REFERENCES apps_description(app_id);


-- Table app_categories
DESCRIBE apps_categories; -- No key is set

# Since the relation between app_id and category_id is 1:1
# I integrate category_id insime app_description
ALTER TABLE apps_categories
CHANGE category_id category_id VARCHAR(100); -- First I change the category type

ALTER TABLE apps_description
ADD COLUMN category_id VARCHAR(100) NOT NULL; -- Then I add the column in the apps_description table

UPDATE apps_description AS a
JOIN apps_categories AS b
  ON a.app_id = b.app_id
SET a.category_id = b.category_id; -- Lastly, I populate the column


-- Table new_categories
DESCRIBE new_categories;

ALTER TABLE new_categories
DROP COLUMN macro_category;

DELETE FROM new_categories
WHERE id = 'f2d792092fa38504913a64696fb8857e' 
LIMIT 1;

ALTER TABLE new_categories
CHANGE id category_id VARCHAR(100),
ADD PRIMARY KEY(category_id); -- Changing category id name and type


-- Table categories_macro
DESCRIBE categories_macro; 

-- Table categories_mapping
DESCRIBE categories_mapping;

ALTER TABLE categories_mapping
  ADD CONSTRAINT fk_mapping_macro
  FOREIGN KEY (id_macro) REFERENCES categories_macro(id_macro);


-- Table clustered_categories
DESCRIBE clustered_categories2;

ALTER TABLE clustered_categories2
  ADD PRIMARY KEY (id_category);
  
  
-- ================
-- 2. JOINS
-- ================

# Joining Apps description with prices and reviews
# Since the relations are 1:N, I only select summaries
# I Will use LEFT JOINS on the app_category since I want to keep everything that is in the main table

SELECT 
	ad.app_id,
    ad.title,
    ad.developer,
    ad.rating,
    ad.reviews_count,
    ad.free_to_install,
    ad.has_free_trial,
    ad.has_free_plan,
    ad.has_multiple_plans,
    ad.is_completely_free,
    ad.billing_type, 
    ad.price_raw,
    ad.price_numeric,
    ad.monthly_price,
    ad.category_id,
    pp2.price_numeric_pp2,
	pp2.number_of_plans,
	pp2.is_free_pp2,
	pp2.has_multiple_plans_pp2,
	pp2.has_free_plan_pp2,
    pp2.has_base_plan_pp2,
    re.avg_rating_re,
    re.reviews_count_re
FROM apps_description AS ad
JOIN (
	SELECT app_id, 
		AVG(price_numeric) AS price_numeric_pp2,
		COUNT(title) AS number_of_plans,
		AVG(is_free) AS is_free_pp2,
		AVG(has_multiple_plans) AS has_multiple_plans_pp2,
		AVG(has_free_plan) AS has_free_plan_pp2,
		AVG(has_base_plan) AS has_base_plan_pp2
    FROM pricing_plans2
    GROUP BY app_id
) pp2
  ON ad.app_id = pp2.app_id
JOIN (
	SELECT app_id,
		AVG(rating) AS avg_rating_re,
        COUNT(rating) AS reviews_count_re
	FROM reviews_edited
    GROUP BY app_id
) re
  ON ad.app_id = re.app_id;
  
  ## It is worth noticing that the average review rating does not match
  # even though the number of reviews does
  # Moreover, the price diverges since app_description stores only one of the pricing plans
  # I consider both the average ratings and the price from their respective tables to be more reliable
  
  SELECT *
  FROM apps_description AS ad
  JOIN clustered_categories2 AS cc2
    ON ad.category_id = cc2.id_category;
    
    
-- ================
-- 3. EXPORTING TABLES
-- ================  

-- app_description, pricing_plans, reviews_edited
(SELECT 'ad.app_id', 'ad.title', 'ad.developer', 'ad.rating', 'ad.reviews_count', 'ad.free_to_install',
 'ad.has_free_trial', 'ad.has_free_plan', 'ad.has_multiple_plans', 'ad.is_completely_free', 'ad.billing_type', 'ad.price_raw',
 'ad.price_numeric', 'ad.monthly_price', 'ad.category_id', 'pp2.price_numeric_pp2', 'pp2.number_of_plans', 'pp2.is_free_pp2',
 'pp2.has_multiple_plans_pp2', 'pp2.has_free_plan_pp2', 'pp2.has_base_plan_pp2', 're.avg_rating_re', 're.reviews_count_re')
 UNION
 (SELECT 
	ad.app_id, ad.title, ad.developer, ad.rating,
    ad.reviews_count, ad.free_to_install,
    IFNULL(ad.has_free_trial, ''), ad.has_free_plan, ad.has_multiple_plans,
    ad.is_completely_free, ad.billing_type, 
    IFNULL(ad.price_raw, ''), ad.price_numeric,
    IFNULL(ad.monthly_price, ''), ad.category_id,
    pp2.price_numeric_pp2, pp2.number_of_plans,
	pp2.is_free_pp2, pp2.has_multiple_plans_pp2,
	pp2.has_free_plan_pp2, pp2.has_base_plan_pp2,
    re.avg_rating_re, re.reviews_count_re
FROM apps_description AS ad
JOIN (
	SELECT app_id, 
		AVG(price_numeric) AS price_numeric_pp2,
		COUNT(title) AS number_of_plans,
		AVG(is_free) AS is_free_pp2,
		AVG(has_multiple_plans) AS has_multiple_plans_pp2,
		AVG(has_free_plan) AS has_free_plan_pp2,
		AVG(has_base_plan) AS has_base_plan_pp2
    FROM pricing_plans2
    GROUP BY app_id
) pp2
  ON ad.app_id = pp2.app_id
JOIN (
	SELECT app_id,
		AVG(rating) AS avg_rating_re,
        COUNT(rating) AS reviews_count_re
	FROM reviews_edited
    GROUP BY app_id
) re
  ON ad.app_id = re.app_id)
  INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/apps_description_prices_reviews.csv'
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n';

-- app_description and clustered_categories2
(SELECT 'app_id', 'title', 'developer', 'rating', 'reviews_count',
 'lastmod', 'free_to_install', 'has_free_trial', 'has_free_plan',
 'is_completely_free', 'billing_type', 'price_raw', 'price_numeric',
 'monthly_price', 'category_id', 'has_multiple_plans', 'id_macro', 'macro_category') -- Column Headers
UNION
(SELECT app_id, ad.title, developer, rating, reviews_count, 
		lastmod, free_to_install, IFNULL(has_free_trial, ''), IFNULL(has_free_plan, ''),
        is_completely_free, billing_type, IFNULL(price_raw, ''), price_numeric, IFNULL(monthly_price, ''), category_id, 
        IFNULL(has_multiple_plans, ''), cc2.id_macro, cc2.macro_category
	FROM apps_description AS ad
  JOIN clustered_categories2 AS cc2
    ON ad.category_id = cc2.id_category)
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/apps_description_categories.csv'
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n';


-- app_description table
(SELECT 'app_id', 'url', 'title', 'developer', 'developer_link', 'icon', 'rating', 'reviews_count', 'description',
 'tag_line', 'pricing', 'lastmod', 'free_to_install', 'has_free_trial', 'has_free_plan',
 'is_completely_free', 'billing_type', 'price_raw', 'price_numeric', 'monthly_price', 'category_id', 'has_multiple_plans')
UNION 
(SELECT app_id, url, title, IFNULL(developer, ''), IFNULL(developer_link, ''), IFNULL(icon, ''), 
    IFNULL(rating, ''), IFNULL(reviews_count, ''), IFNULL(description, ''), 
    IFNULL(tag_line, ''), IFNULL(pricing, ''), IFNULL(lastmod, ''), IFNULL(free_to_install, ''), 
    IFNULL(has_free_trial, ''), IFNULL(has_free_plan, ''), IFNULL(is_completely_free, ''), 
    IFNULL(billing_type, ''), IFNULL(price_raw, ''), IFNULL(price_numeric, ''), 
    IFNULL(monthly_price, ''), IFNULL(category_id, ''), IFNULL(has_multiple_plans, '')
    FROM apps_description)
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/apps_description.csv'
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n';

(SELECT 'app_id', 'url', 'title', 'developer', 'developer_link', 'icon', 'rating', 'reviews_count', 'description',
 'tag_line', 'pricing', 'lastmod', 'free_to_install', 'has_free_trial', 'has_free_plan',
 'is_completely_free', 'billing_type', 'price_raw', 'price_numeric', 'monthly_price', 'category_id', 'has_multiple_plans')
UNION 
(SELECT 
    app_id, 
    url, 
    title, 
    IFNULL(developer, ''), 
    IFNULL(developer_link, ''), 
    IFNULL(icon, ''), 
    IFNULL(rating, ''), 
    IFNULL(reviews_count, ''), 
    -- Clean out newlines and carriage returns from descriptions
    REPLACE(REPLACE(IFNULL(description, ''), '\n', ' '), '\r', ' '), 
    IFNULL(tag_line, ''), 
    IFNULL(pricing, ''), 
    IFNULL(lastmod, ''), 
    IFNULL(free_to_install, ''), 
    IFNULL(has_free_trial, ''), 
    IFNULL(has_free_plan, ''), 
    IFNULL(is_completely_free, ''), 
    IFNULL(billing_type, ''), 
    IFNULL(price_raw, ''), 
    IFNULL(price_numeric, ''), 
    IFNULL(monthly_price, ''), 
    IFNULL(category_id, ''), 
    IFNULL(has_multiple_plans, '')
    FROM apps_description)
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/apps_description.csv'
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"' 
ESCAPED BY '"' -- This forces double-quotes to escape themselves (standard CSV behavior)
LINES TERMINATED BY '\r\n'; -- Standard Windows line endings

-- clustered_categories2
(SELECT 'id_category', 'title', 'cluster_agglomerate', 'cluster_agglomerate_cosine',
 'cluster_hdbscan', 'macro_category_agg', 'macro_category_agg1', 'macro_category_hdbscan', 'id_macro', 'macro_category')
 UNION
(SELECT id_category, title, cluster_agglomerate, cluster_agglomerate_cosine, cluster_hdbscan,
 macro_category_agg, macro_category_agg1, macro_category_hdbscan, id_macro, macro_category
 FROM clustered_categories2)
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/clustered_categories.csv'
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n';

-- pricing_plans2
(SELECT 'pricing_id', 'app_id', 'title', 'price', 'billing_type', 'price_raw', 'price_numeric', 'monthly_price',
 'number_of_plans', 'title_category', 'is_free', 'has_multiple_plans', 'has_free_plan', 'has_base_plan')
 UNION
(SELECT pricing_id, app_id, title, price, billing_type, IFNULL(price_raw, '') , price_numeric, IFNULL(monthly_price, ''), 
number_of_plans, title_category, is_free, has_multiple_plans, has_free_plan, has_base_plan
FROM pricing_plans2)
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/pricing_plans2.csv'
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n';

-- reviews_edited
(SELECT 'review_id', 'app_id', 'author', 'rating', 'posted_at', 'body', 'helpful_count', 'developer_reply',
 'developer_reply_posted_at', 'avg_rating', 'number_of_ratings', 'has_dev_replied', 'posted_date')
 UNION
(SELECT review_id, app_id, IFNULL(author, ''), rating, posted_at, IFNULL(body, ''), IFNULL(helpful_count, ''), IFNULL(developer_reply, ''), 
IFNULL(developer_reply_posted_at,''), avg_rating, number_of_ratings, IFNULL(has_dev_replied, ''), posted_date
FROM reviews_edited)
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/reviews_edited.csv'
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n';

(SELECT 'review_id', 'app_id', 'author', 'rating', 'posted_at', 'body', 'helpful_count', 'developer_reply',
 'developer_reply_posted_at', 'avg_rating', 'number_of_ratings', 'has_dev_replied', 'posted_date')
 UNION
(SELECT review_id, app_id, IFNULL(author, ''), rating, posted_at, IFNULL(body, ''), IFNULL(helpful_count, ''), IFNULL(developer_reply, ''), 
IFNULL(developer_reply_posted_at,''), avg_rating, number_of_ratings, IFNULL(has_dev_replied, ''), posted_date
FROM reviews_edited)
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/reviews_edited.csv'
FIELDS TERMINATED BY ',' 
OPTIONALLY ENCLOSED BY '"' -- This wraps your 'body' text in "quotes"
ESCAPED BY '\\'
LINES TERMINATED BY '\n';