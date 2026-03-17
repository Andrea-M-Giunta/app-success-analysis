-- ==================
-- 1. SCHEMA SETUP
-- ==================
SET GLOBAL local_infile = 1;

-- CREATING TABLES 
CREATE TABLE apps (
    id VARCHAR(100) PRIMARY KEY,
    url VARCHAR(500),
    title VARCHAR(255),
    developer VARCHAR(255),
    developer_link VARCHAR(500),
    icon VARCHAR(500),
    rating DECIMAL(3, 2), 
    reviews_count INT,
    description_raw TEXT,
    description TEXT,
    tag_line VARCHAR(500),
    pricing VARCHAR(500), 
    lastmod VARCHAR(100)
);

CREATE TABLE reviews (
    app_id VARCHAR(100),
    author VARCHAR(255),
    rating DECIMAL(3, 2),
    posted_at VARCHAR(100),
    body TEXT,
    helpful_count INT NULL,
    developer_reply TEXT,
    developer_reply_posted_at VARCHAR(100)
);

CREATE TABLE pricing_plans (
	id VARCHAR(100) PRIMARY KEY,
    app_id VARCHAR(100),
    title TEXT,
    price VARCHAR(500)
);

    
-- LOADING DATA
# Table apps
LOAD DATA LOCAL INFILE 'C:/Users/andre/OneDrive/Documenti/9. Datasets/shopify-app-analysis/data/raw/apps.csv'
INTO TABLE apps
CHARACTER SET utf8mb4 
FIELDS TERMINATED BY ',' 
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' -- Changed to Windows standard
IGNORE 1 ROWS;

# Table reviews
LOAD DATA LOCAL INFILE 'C:/Users/andre/OneDrive/Documenti/9. Datasets/shopify-app-analysis/data/raw/reviews.csv'
INTO TABLE reviews
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' 
OPTIONALLY ENCLOSED BY '"'
ESCAPED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(app_id, author, rating, posted_at, body, @vhelpful_count, developer_reply, developer_reply_posted_at)
SET helpful_count = NULLIF(@vhelpful_count, '');

# Pricing plans
LOAD DATA LOCAL INFILE 'C:/Users/andre/OneDrive/Documenti/9. Datasets/shopify-app-analysis/data/raw/pricing_plans.csv'
INTO TABLE pricing_plans
CHARACTER SET utf8mb4 
FIELDS TERMINATED BY ',' 
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n' -- Changed to Windows standard
IGNORE 1 ROWS;

-- ==================
-- 2. DATA CLEANING
-- ==================

-- Apps Table =========
SELECT *
FROM apps;

# Duplicate raw table to work on it
CREATE TABLE apps_description
LIKE apps;

INSERT apps_description
SELECT *
FROM apps;

SELECT *
FROM apps_description;

# Check duplicates
UPDATE apps_description
SET
	id = TRIM(id),
    title = TRIM(title),
    developer = TRIM(developer);
    
SELECT 
    id, 
    COUNT(id)
FROM
    apps_description
GROUP BY id
HAVING COUNT(id) > 1; -- no duplicates found

SELECT 
	description_raw, 
    description
FROM apps_description;

# Parsing dates
SELECT 
	lastmod, 
    str_to_date(lastmod, '%m/%d/%Y')
FROM apps_description;

UPDATE apps_description
SET lastmod = str_to_date(lastmod, '%m/%d/%Y');

SELECT *
FROM apps_description;

## Dealing with pricing
SELECT DISTINCT pricing
FROM apps_description;

# Adding boolean columns
ALTER TABLE apps_description
ADD column is_completely_free TINYINT,
ADD column free_to_install TINYINT,
ADD column has_free_trial TINYINT,
ADD column has_free_plan TINYINT,
ADD column has_multiple_plans TINYINT;

# Populate boolean columns
UPDATE apps_description
SET 
	is_completely_free = pricing LIKE '%Price: Free%',
	free_to_install = pricing LIKE '%Free to install%',
    has_free_trial = pricing LIKE '%Free trial%',
    has_free_plan = pricing LIKE '%Free plan%',
    has_multiple_plans = pricing LIKE '%From%'; -- From indicates that there are multiple plan even though we don't know what they aree
    
SELECT DISTINCT
	pricing,
    is_completely_free,
	free_to_install,
    has_free_trial,
    has_free_plan,
    has_multiple_plans
FROM apps_description;

# Updating values when we don't know exactly
SELECT DISTINCT pricing
FROM apps_description
WHERE pricing LIKE '%Additional charges may apply%';

UPDATE apps_description
SET 
    has_free_trial = NULL,
    has_free_plan = NULL,
    has_multiple_plans = NULL
WHERE pricing LIKE '%Additional charges may apply%';

# Update free to install when app is free
UPDATE apps_description
SET
	free_to_install = 1
WHERE is_completely_free = 1;

SELECT DISTINCT
	pricing,
    is_completely_free,
	free_to_install,
    has_free_trial,
    has_free_plan,
    has_multiple_plans
FROM apps_description;
    
    
# Adding billing type column
ALTER TABLE apps_description
ADD column billing_type VARCHAR(50);

SELECT DISTINCT pricing
FROM apps_description
WHERE billing_type LIKE '%other%';

UPDATE apps_description
SET billing_type =
	CASE
		WHEN pricing LIKE '%one-time%' THEN 'one_time'
        WHEN pricing LIKE '%month%' THEN 'monthly'
        WHEN pricing LIKE '%year%' THEN 'yearly'
        WHEN is_completely_free = 1 THEN 'free'
        ELSE 'other'
	END;

SELECT DISTINCT
	pricing,
    is_completely_free,
	free_to_install,
    has_free_trial,
    has_free_plan,
    has_multiple_plans,
    billing_type
FROM apps_description;

UPDATE apps_description
SET has_multiple_plans = NULL 
WHERE billing_type LIKE '%other%' AND pricing LIKE '%free%';

# Extracting price
SELECT
	DISTINCT pricing,
	CAST(REPLACE(REGEXP_SUBSTR(pricing, '[0-9]{1,3}(,[0-9]{3})*(\\.[0-9]+)?'), ',','') AS DECIMAL(10,2)) AS price_numeric
FROM apps_description
ORDER BY CAST(REPLACE(REGEXP_SUBSTR(pricing, '[0-9]{1,3}(,[0-9]{3})*(\\.[0-9]+)?'), ',','') AS DECIMAL(10,2)) DESC; -- To determine the digits of the numbers

ALTER TABLE apps_description
ADD COLUMN price_raw DECIMAL(10, 2), -- When app free then price_raw missing
ADD COLUMN price_numeric DECIMAL(10, 2), -- When app free then price 0
ADD COLUMN monthly_price DECIMAL(10, 2); -- To have year prices into montly prices

UPDATE apps_description
SET price_raw = CAST(
      REPLACE(
          REGEXP_SUBSTR(pricing, '[0-9]{1,3}(,[0-9]{3})*(\\.[0-9]+)?'),
          ',', ''
      ) AS DECIMAL(10,2)
);

UPDATE apps_description
SET 
  monthly_price = 
  CASE 
	WHEN billing_type LIKE 'yearly' THEN price_raw / 12
    ELSE price_raw
  END;
  
UPDATE apps_description
SET
	price_numeric = 0 
WHERE is_completely_free = 1;

SELECT 
	DISTINCT pricing,
	is_completely_free,
	free_to_install,
    has_free_trial,
    has_free_plan,
    has_multiple_plans,
	price_raw,
	price_numeric,
	monthly_price,
    billing_type
FROM apps_description;

SELECT *
FROM apps_description;


-- Pricing Plans Table ==========
SELECT *
FROM pricing_plans;

SELECT DISTINCT price
FROM pricing_plans
WHERE price LIKE '%free%';

CREATE TABLE pricing_plans2
LIKE pricing_plans;

INSERT pricing_plans2
SELECT *
FROM pricing_plans;

# Creating new columns to classify pricies
ALTER TABLE pricing_plans2
ADD column billing_type VARCHAR(50),
ADD COLUMN price_raw DECIMAL(10, 2), -- When app free then price_raw is missing
ADD COLUMN price_numeric DECIMAL(10, 2), -- When app free then price 0
ADD COLUMN monthly_price DECIMAL(10, 2); -- To have year prices into montly prices

SET SQL_SAFE_UPDATES = 0;

# Populating billing type
UPDATE pricing_plans2
SET billing_type =
	CASE
		WHEN price LIKE '%one-time%' THEN 'one time'
        WHEN price LIKE '%month%' THEN 'monthly'
        WHEN price LIKE '%year%' THEN 'yearly'
        WHEN price LIKE '%free%' THEN 'free'
        ELSE 'other'
	END;


# Populating price raw
UPDATE pricing_plans2
SET price_raw = CAST(
      REPLACE(
          REGEXP_SUBSTR(price, '[0-9]{1,3}(,[0-9]{3})*(\\.[0-9]+)?'),
          ',', ''
      ) AS DECIMAL(10,2)
);

# Populating price numeric
UPDATE pricing_plans2
SET 
	price_numeric =
    CASE
		WHEN billing_type LIKE 'free' THEN 0
        ELSE price_raw
	END;

# Populating monthly price
UPDATE pricing_plans2
SET 
  monthly_price = 
  CASE 
	WHEN billing_type LIKE 'yearly' THEN price_raw / 12
    WHEN billing_type LIKE '%one%' THEN NULL
    ELSE price_raw
  END;

SELECT *
FROM pricing_plans2;

## Text normalization
UPDATE pricing_plans2
SET title = LOWER(TRIM(title));

SELECT DISTINCT title
FROM pricing_plans2;

# Check which app has multiple plans
SELECT app_id, COUNT(*) AS numer_of_plans
FROM pricing_plans2
GROUP BY app_id
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;
    
# Create a column to group plans
ALTER TABLE pricing_plans2
ADD COLUMN number_of_plans INT; -- Since plans have different names, their classification may change from app to app
							   -- I present seven groups: free, single plan, tier 1, tier 2, tier 3, one time, other.

UPDATE pricing_plans2 p
JOIN (
    SELECT app_id, COUNT(*) as total
    FROM pricing_plans
    GROUP BY app_id
) AS counts 
  ON p.app_id = counts.app_id
SET p.number_of_plans = counts.total;

SELECT * 
FROM pricing_plans2
WHERE number_of_plans = 2; 

SELECT *
FROM pricing_plans2
WHERE number_of_plans = 1; 

# Create columns to classify pricing plans
ALTER TABLE pricing_plans2
ADD COLUMN title_category VARCHAR(100),
ADD COLUMN is_free TINYINT, -- If an app has only 1 plan and it's free
ADD COLUMN has_multiple_plans TINYINT,
ADD COLUMN has_free_plan TINYINT, -- If an app has multiple plans but one is free
ADD COLUMN has_base_plan TINYINT; -- If an app has multiple plans but the cheapest one is not free

# Hard coding some categories
UPDATE pricing_plans2
SET 
	title_category =
    CASE
		WHEN number_of_plans = 1 THEN
        CASE
			WHEN billing_type LIKE 'free' THEN 'free' -- Avoids language differences
			WHEN title LIKE '%one-time%' THEN 'one time'
			ELSE 'single plan'
		END
		WHEN number_of_plans > 1 THEN 'multiple plans'
	END;


# Populating dummy variabiles
UPDATE pricing_plans2 
	SET 
		is_free = 0,
		has_free_plan = 0,
        has_base_plan = 0,
        has_multiple_plans = 0; -- Setting all base values to 0
	
UPDATE pricing_plans2
SET is_free = 1 
WHERE title_category LIKE 'free'; -- completely free

UPDATE pricing_plans2
SET has_multiple_plans = 1 
WHERE number_of_plans > 1; -- multiple plans

UPDATE pricing_plans2 p
JOIN (
    SELECT DISTINCT app_id
    FROM pricing_plans2
    WHERE price_numeric = 0
      AND number_of_plans > 1
) free_apps ON p.app_id = free_apps.app_id
SET p.has_free_plan = 1; -- Setting 1 to those apps that have multiple plans but one of them is free

UPDATE pricing_plans2 p
JOIN (
    SELECT DISTINCT app_id
    FROM pricing_plans2
    WHERE has_free_plan = 0 AND has_multiple_plans = 1
) free_apps ON p.app_id = free_apps.app_id
SET p.has_base_plan = 1; -- Setting 1 to those apps that have only payment plans


SELECT *
FROM pricing_plans2;

-- Table reviews =======
CREATE TABLE reviews_edited
LIKE reviews;

INSERT reviews_edited
SELECT *
FROM reviews;

DESCRIBE reviews_edited;


# Create ID primary key
SET GLOBAL net_read_timeout = 4200;
SET GLOBAL net_write_timeout = 4200;
SET GLOBAL wait_timeout = 4200;
SET GLOBAL interactive_timeout = 4200;  -- Since the table is very long it may take a while to create the id

ALTER TABLE reviews_edited
ADD COLUMN review_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY FIRST;

DESCRIBE reviews_edited;

SELECT *
FROM reviews_edited;

# Create columns to analyze
ALTER TABLE reviews_edited
ADD COLUMN avg_rating DECIMAL (3, 2),
ADD COLUMN number_of_ratings INT,
ADD COLUMN has_dev_replied TINYINT; -- Dummy to check wheter author has replied

# Populate based on developers' replies
UPDATE reviews_edited
SET has_dev_replied = (
    developer_reply IS NOT NULL 
    AND TRIM(developer_reply) <> ''
)
WHERE review_id > 0;

# Populate average and count
UPDATE reviews_edited t1
JOIN (
    SELECT 
        review_id,
        AVG(rating) OVER(PARTITION BY app_id) as c_avg,
        COUNT(rating) OVER(PARTITION BY app_id) as c_count
    FROM reviews_edited
) t2 ON t1.review_id = t2.review_id
SET t1.avg_rating = t2.c_avg,
    t1.number_of_ratings = t2.c_count
WHERE t1.review_id > 0; 

# Parsing Dates
SELECT developer_reply_posted_at, REPLACE(developer_reply_posted_at,',','') -- Developer is easier to deal with since there are no edits
																			-- for the date posted I will create a new column and parse only not edited ones
FROM reviews_edited;

UPDATE reviews_edited
SET 
	developer_reply_posted_at = LOWER(REPLACE(TRIM(developer_reply_posted_at),',','')),
    posted_at = LOWER(REPLACE(TRIM(posted_at),',',''))
WHERE review_id > 0; -- Standardizing text

UPDATE reviews_edited 
SET developer_reply_posted_at = NULL 
WHERE TRIM(developer_reply_posted_at) = '' AND review_id > 0; -- Clean string

UPDATE reviews_edited
SET developer_reply_posted_at = str_to_date(developer_reply_posted_at, "%M %d %Y")
WHERE review_id > 0; -- Parsing date

ALTER TABLE reviews_edited 
MODIFY COLUMN developer_reply_posted_at DATE; -- Update type 

ALTER TABLE  reviews_edited
ADD COLUMN posted_date DATE; -- adding new column to not lose info on posted_at

UPDATE reviews_edited
SET posted_date = str_to_date(posted_at, "%M %d %Y")
WHERE posted_at NOT LIKE '%Edited%'
  AND review_id > 0; -- Parsing only dates that are not edited

SELECT *
FROM reviews_edited;

# Cleaning text
UPDATE reviews_edited
SET body = REGEXP_REPLACE(body, '[-/_*"\\\\]', ' ');

UPDATE reviews_edited
SET developer_reply = REGEXP_REPLACE(body, '[-/_*"\\\\]', ' '); -- This avoids problem also during the export of the dataset

# Create Developer response rate
SELECT app_id, COUNT(has_dev_replied) AS dev_responses
FROM reviews_edited
GROUP BY app_id;

SELECT
	app_id, 
	SUM(has_dev_replied) AS dev_responses,
    AVG(number_of_ratings),
    SUM(has_dev_replied) / AVG(number_of_ratings) * 100 AS dev_responses_rate,
    AVG(rating)
FROM reviews_edited
GROUP BY app_id;

SELECT
	app_id, 
	SUM(has_dev_replied) AS dev_responses,
    AVG(number_of_ratings),
    SUM(has_dev_replied) / AVG(number_of_ratings) * 100 AS dev_responses_rate,
    AVG(rating)
FROM reviews_edited
GROUP BY app_id
HAVING AVG(number_of_ratings) > 10;

-- Table Apps Categories ========
SELECT *
FROM apps_categories;

SELECT *
FROM categories;

# Create copy of categories to work on
CREATE TABLE new_categories
LIKE categories;

INSERT new_categories
SELECT *
FROM categories;

SELECT *
FROM new_categories;

# Normalize text
UPDATE new_categories
SET
	id = TRIM(id),
    title = LOWER(TRIM(title)); -- Lower case and trim spaces

UPDATE new_categories
SET title = 
	REPLACE(
    REPLACE(
      REPLACE(title, '-', ' '),
    '/', ' '),
  '  ', ' '); -- Remnove dash, double spaces and slash
  
# Create new column to store macro categories
ALTER TABLE new_categories
ADD COLUMN macro_category VARCHAR(100);

SELECT DISTINCT title
FROM new_categories;

### Important Note
# Populating the macro category column in SQL cannot be done effectively sicnce 
# each title is unique in the choice of words and it cannot be achieved by
# normalizing the text
# Therefore, I performed a Text classification in Python using BERT classification models
# to derive a new data set named 'clustered_categories'
# hereby I cleaned it and map it

-- Table clustered_ categories =====
SELECT *
FROM clustered_categories;

# Create duplicate to work on
CREATE TABLE clustered_categories2
LIKE clustered_categories;

INSERT clustered_categories2
SELECT *
FROM clustered_categories;

# Standardizing and improving readibility macro categories
UPDATE clustered_categories2
SET	macro_category_hdbscan = 
    TRIM(
    REPLACE(
    REPLACE(
      REPLACE(macro_category_hdbscan, '-', ' '),
    '/', ' '),
  '  ', ' ')
  ); -- these names were generated using the shortest name in the cluster
  
UPDATE clustered_categories2
SET macro_bertopic = 
		REPLACE(
        REPLACE(
        REPLACE(
        REPLACE(macro_bertopic, '-', ' '), '/', ' '), '  ', ' '), '_', ' ');
        
UPDATE clustered_categories2
SET macro_bertopic = TRIM(REGEXP_REPLACE(macro_bertopic, '[0-9]+', ' ')); -- removing numbers from betropic
																   -- these names were generated automatically by bertopic
																
SELECT *
FROM clustered_categories2;

# Changing columns name
ALTER TABLE clustered_categories2
CHANGE cluster_bertopic id_macro INT,
CHANGE macro_bertopic macro_category TEXT,
CHANGE id id_category TEXT;

#Dropping duplicates
SELECT id_category, COUNT(id_category)
FROM clustered_categories2
GROUP BY id_category
HAVING COUNT(id_category) > 1;

DELETE FROM clustered_categories2
WHERE id_category = 'f2d792092fa38504913a64696fb8857e' 
LIMIT 1; -- Deletes only one copy of the duplicated row since every other value is equal

ALTER TABLE clustered_categories2
CHANGE COLUMN id_category id_category VARCHAR(100);

DESCRIBE clustered_categories2;

# Analyse Category competition
SELECT 
	COUNT(id_category) AS apps_per_category,
    macro_category
FROM clustered_categories2
GROUP BY macro_category;

-- Create master and mapping tables ====
# This is necessary since I've created macro categories with new ids

# Table with unique macro id and titles
CREATE TABLE categories_macro (
	id_macro INT PRIMARY KEY,
    macro_category VARCHAR(200)
);

INSERT categories_macro
SELECT DISTINCT id_macro, macro_category
FROM clustered_categories2; 

# Table mapping categories and macro categories
CREATE TABLE categories_mapping (
	id_category VARCHAR(100) PRIMARY KEY,
    id_macro INT
);

INSERT categories_mapping
SELECT DISTINCT id_category, id_macro
FROM clustered_categories2;