######################################
# Project: Shopify App Market
# File name: 1.eda
# date: 02-2026
# author: Andrea M. Giunta
#######################################

####################
### 1. Library ----

library(tidyverse)
library(ggplot2)
library(factoextra)
library(boot)
library(class)
library(readr)
library(tree)
library(here)
library(janitor)
library(data.table)
library(skimr)

###################
### 2. Loading data ----
### 2.1 Load apps_description Table

apps_description <- read_csv(
    here("data/processed", "apps_description.csv")
)
    dim(apps_description)
    head(apps_description)
    View(apps_description)

# Copy with selected columns
apps <- apps_description[, -c(2, 5:6, 9:10)]
    dim(apps)

apps$lastmod <- as.Date(apps$lastmod)
    View(apps)
    
# Count number of developers
length(unique(apps$developer)) #7,697 developer for 11,951 apps

# Time span of last mod
min(apps$lastmod)
max(apps$lastmod)

# The dataset was last updated on 2024-11-28
# So we can compute the time between updates
last_data_update <- as.Date("2024-11-28")

apps <- apps %>%
    mutate(
        days_since_update = as.numeric(last_data_update - lastmod)
    )

cor(apps$days_since_update, apps$rating)
        #negative correlation, althoug not too strong


# As noted in the SQL query:
# The apps_description table has prices columns but they show only one tier
# therefore it's hard to compare apps and costruct medium prices
# Also the category ID is unique so it does not provide any additional info
# => I will merge the other tables

### 2.2 Load clustered_categories table
categories <- read_csv(
    here("data/processed", "clustered_categories2.csv")
)

dim(categories)
View(categories)

# Select only macro categories since categories are unique for each app
macro_categories <- categories[, c(1, 9:10)]
View(macro_categories)

## Merge apps and macro categories
apps_macro <- apps %>%
    left_join(macro_categories, by = c("category_id" = "id_category"))

dim(apps_macro)
View(apps_macro)

sort(unique(macro_categories$id_macro))
sort(unique(apps_macro$id_macro)) # some macro categories are not present
                                  # in the app dataframe

# Rows of macro that did not match with rows in apps
check_macro <- macro_categories %>%
  anti_join(apps, by = c("id_category" = "category_id"))
  
dim(check_macro)
View(check_macro)

# Category competition
category_competition <- apps_macro %>%
    group_by(id_macro) %>%
    summarise(n_apps = n())

View(category_competition)


### 2.3 Load reviews_edited table
reviews_edited <- fread(
    here("data/processed", "reviews_edited.csv"),
    quote = '"'
)
dim(reviews_edited)
colnames(reviews_edited)
View(head(reviews_edited, 1000))

# removing null column and string date
reviews_edited <- reviews_edited[, -c(5, 7)]

# conventing string to date
reviews_edited$posted_date <- as.Date(reviews_edited$posted_date)

# Time between posted review and reply
reviews_edited <- reviews_edited %>%
    mutate(
        reply_time = as.numeric(developer_reply_posted_at - posted_date)
    )

# Total replies by app
reviews_edited <- reviews_edited %>%
    group_by(app_id) %>%
    mutate(total_replies = sum(has_dev_replied, na.rm = TRUE)) %>%
    ungroup() #replies by app

# I'll keep this dataframe to perform sentiment analysis 
# and use a copy of it with only aggregated results to merge

reviews <- reviews_edited[, c(1:2, 4, 7:13)]
View(head(reviews))

# Aggregated dataframe
reviews_aggregated <- reviews %>%
    select(2, 5:6, 9:10) %>%
    group_by(app_id) %>%
    summarise(
        avg_rating = mean(avg_rating, na.rm = TRUE),
        number_of_ratings = mean(number_of_ratings, na.rm = TRUE),
        avg_reply_time = mean(reply_time, na.rm = TRUE),
        total_replies = mean(total_replies, na.rm = TRUE)
    )

view(reviews_aggregated)

# Developer response rate
reviews_aggregated <- reviews_aggregated %>%
  mutate(response_rate = (total_replies / number_of_ratings) * 100)


### 2.4 Load pricing_plans table
pricing_plans <- read_csv(
    here("data/processed", "pricing_plans2.csv")
)
dim(pricing_plans)
View(pricing_plans)

# Genearte dummy for one time paymnent since
# billing type cannot be used in the aggregate verion of the dataset

pricing_plans <- pricing_plans %>%
    mutate(one_time = if_else(billing_type == "one time", 1, 0))

# Aggregate pricing plans at app id level
pricing_aggregates <- pricing_plans %>%
    select(2, 5:9, 11:15) %>%
    group_by(app_id) %>%
    summarise(
        app_price_raw = round(mean(price_raw, na.rm = TRUE), digits = 2),
        app_price_numeric = round(mean(price_numeric, na.rm = TRUE), digits = 2),
        app_price_monthly = round(mean(monthly_price, na.rm = TRUE), digits = 2),
        is_one_time = mean(one_time, na.rm = TRUE),
        number_of_plans = mean(number_of_plans, na.rm = TRUE),
        is_free = mean(is_free, na.rm = TRUE),
        has_multiple_plans = mean(has_multiple_plans, na.rm = TRUE),
        has_free_plan = mean(has_free_plan, na.rm = TRUE),
        has_base_plan = mean(has_base_plan, na.rm = TRUE)
    )
dim(pricing_aggregates)
View(pricing_aggregates)

## Key benefits
# This table was untouched in the SQL part
# For this analysis I just count the number of feature for
# each app whcih gives a proxy of complexity
# A more in depth analysis would be to understand the
# feature and weight them
# but for the moment it is not necessary

key_benefits <- read_csv(here("data/raw", "key_benefits.csv"))
View(key_benefits)

# a bit of cleaning
key_benefits <- key_benefits %>%
  mutate(description_cleaned = description %>%
    str_to_lower() %>%
    str_replace_all("http\\S+|www\\S+", "") %>% # Remove URLs
    str_replace_all("[^\x01-\x7F]", "") %>% # Remove non-ASCII
    str_replace_all("[[:punct:]]", "") %>% # Remove punctuation
    str_squish() # Remove extra spaces
  )

# dropping empty rows
key_benefits <- key_benefits %>%
  mutate(description_cleaned = na_if(description_cleaned, "")) %>%
  drop_na(description_cleaned)

# deriving number of benefits
benefits <- key_benefits %>%
    group_by(app_id) %>%
    summarise(number_of_benefits = n_distinct(description_cleaned))
View(benefits)
summary(benefits$number_of_benefits)

###################
### 3. Merging into a single dataset ----
# I already merged apps and categories
# but I want to create a comprehensive dataset with also reviews and pricings
# the pricing table would still be usefull to compare apps since it has
# granular data on each data pricing plan while the aggregated dataset
# only has dummy variables and mean pricing

apps_joined <- apps_macro %>%
    left_join(reviews_aggregated, by = "app_id") %>%
    left_join(pricing_aggregates, by = "app_id")

dim(apps_joined)
View(apps_joined)
colnames(apps_joined)

## Confronting original table and table-specific values
# As seen in the SQL query, the ratings in the orginal dataset
# differ from the review table

total_diff <- apps_joined %>%
  summarise(
    diff_rating = mean(abs(rating - avg_rating), na.rm = TRUE),
    diff_reviews = mean(abs(reviews_count - number_of_ratings), na.rm = TRUE),
    diff_price = mean(abs(price_raw - app_price_raw), na.rm = TRUE)
  )

print(total_diff)

## Removing original inexact or reduntant columns
# namely: rating, reviews_count, and pricing variables
apps_joined <- apps_joined[, -c(4:6, 10:17)]
dim(apps_joined)

# renaming columns
apps_joined <- apps_joined %>%
    rename(
        has_multiple_plans = has_multiple_plans.y,
        has_free_plan = has_free_plan.y,
    )
View(apps_joined)

## Correcting dummy variables
# if app free then has free plan and has a base == NaN
apps_joined <- apps_joined %>%
    mutate(
        has_free_plan = if_else(is_free == 1, NA, has_free_plan),
        has_base_plan = if_else(is_free == 1, NA, has_base_plan)
        )


## Merging apps and pricing plans
# To have a merged dataset that contains accurate pricing plans
apps_billings <- apps_macro[, -c(4:6, 8:17)] %>%
  left_join(reviews_aggregated, by = "app_id") %>%
  left_join(pricing_plans, by = "app_id")
View(apps_billings)

colnames(apps_billings)



###################
### 4. Descriptive analysis ----
## ---- Distribution statistics
tabyl(apps_joined, is_free)  #there are 1974 free apps
tabyl(apps_joined, is_one_time) # there are only 78 one time apps
sum(is.na(apps_joined$app_price_numeric)) # there are 2272 mising price data

subs_apps <- apps_joined %>%
    filter(
        is_free == 0 &
        is_one_time == 0 &
        !is.na(app_price_numeric)
    )
view(subs_apps) # -> there are 7627 subscription apps

# Distribution of subscription apps
tabyl(subs_apps, number_of_plans) # 1 and 4 plans are the most popular options

# Pie chart of subscription apps
sub_pie1 <- tabyl(subs_apps, number_of_plans)

ggplot(sub_pie1, aes(x = "", y = n, fill = factor(number_of_plans))) +
  geom_bar(stat = "identity", width = 1, color = "white") +
  coord_polar("y", start = 0) +
  geom_text(aes(label = scales::percent(percent)),
            position = position_stack(vjust = 0.5)) +
  scale_fill_brewer(palette = "Pastel2") +
  theme_void() +
  labs(fill = "Number of plans", title = "Distribution of Number of Plans")

ggsave(
  "pie_chart.png",
  plot = get_last_plot(),
  device = NULL,
  path = here("output/"),
  scale = 1,
  width = NA,
  height = NA,
  units = c("in", "cm", "mm", "px"),
  dpi = 300,
  limitsize = TRUE,
  bg = NULL
)


# of subcription apps with multiple plans
tabyl(subs_apps, has_free_plan) #nearly 46 percent have a free plan

subs_apps %>%
  filter(has_free_plan == 0) %>%
  tabyl(has_free_trial) 
  # Among those w/o free plan most 92 percent have a free trial

# Create freeium apps dataframe
freemium <- subs_apps %>%
    filter(
        has_free_plan == 1
    )

# Create free apps dataframe
free_apps <- apps_joined %>%
    filter(is_free == 1)


## ---- Distribution reviews
summary(apps_joined$number_of_ratings)
hist(apps_joined$number_of_ratings)
# there's a network effect among apps

summary(apps_joined$avg_rating)
hist(apps_joined$avg_rating)
plot(apps_joined$avg_rating, apps_joined$number_of_ratings)
# more popular apps have higher ratings

# adding a line to the plot
ggplot(apps_joined, aes(x = avg_rating, y = number_of_ratings)) +
  geom_point(alpha = 0.3, color = "steelblue") +
  geom_smooth(method = "loess", color = "darkred") +
  scale_y_log10(labels = scales::comma) +
  labs(
    title = "Number of Ratings vs. Average Rating",
    x = "Average Rating",
    y = "Number of Ratings (log scale)"
  ) +
  theme_minimal()

ggsave(
  "ratings_num_avg.png",
  plot = get_last_plot(),
  device = NULL,
  path = here("output/"),
  scale = 1,
  width = NA,
  height = NA,
  units = c("in", "cm", "mm", "px"),
  dpi = 300,
  limitsize = TRUE,
  bg = NULL
)

# Success score measure
# to weight rating by number of reviews
apps_joined <- apps_joined %>%
    mutate(success_score = avg_rating * log(number_of_ratings + 1))

# Free vs freemium vs subscription rating
one_time_app <- apps_joined %>%
    filter(is_one_time == 1)

summary(apps_joined$avg_rating) # all
summary(subs_apps$avg_rating) # apps w/ subscriptions
summary(freemium$avg_rating) # freemium apps
summary(free_apps$avg_rating) # free
summary(one_time_app$avg_rating) # one-time

summary(apps_joined$success_score) # all
summary(subs_apps$success_score) # apps w/ subscriptions
summary(freemium$success_score) # freemium apps
summary(free_apps$success_score) # free
summary(one_time_app$success_score) # one-time

# summary dataframe to store results
rating_summary <- data.frame(
  group = c("All apps", "Subscription", "Freemium", "Free", "One-time"),
  mean  = c(mean(apps_joined$avg_rating, na.rm = TRUE),
            mean(subs_apps$avg_rating,  na.rm = TRUE),
            mean(freemium$avg_rating,   na.rm = TRUE),
            mean(free_apps$avg_rating,  na.rm = TRUE),
            mean(one_time_app$avg_rating,  na.rm = TRUE))
)

succ_score_summary <- data.frame(
  group = c("All apps", "Subscription", "Freemium", "Free", "One-time"),
  mean  = c(mean(apps_joined$success_score, na.rm = TRUE),
            mean(subs_apps$success_score,  na.rm = TRUE),
            mean(freemium$success_score,   na.rm = TRUE),
            mean(free_apps$success_score,  na.rm = TRUE),
            mean(one_time_app$success_score,  na.rm = TRUE))
)

# plotting differences in avg_rating across groups
ggplot(rating_summary, aes(x = group, y = mean, fill = group)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = round(mean, 2)), vjust = -0.5, size = 3.5) +
  labs(title = "Mean rating by app group",
       x = NULL, y = "Mean rating") +
  ylim(0,5) +
  scale_fill_brewer(palette = "Pastel2") +
  theme_minimal()
# free apps are also those with a lower average rating

# plotting differences in success score across groups
ggplot(succ_score_summary, aes(x = group, y = mean, fill = group)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = round(mean, 2)), vjust = -0.5, size = 3.5) +
  labs(title = "Mean success score by app group",
       x = NULL, y = "Mean success score") +
  ylim(0, 16) +
  scale_fill_brewer(palette = "Pastel2") +
  theme_minimal()
# the narrion changes drastically
# freemium apps are those with a higher success score

ggsave(
  "Success_group.png",
  plot = get_last_plot(),
  device = NULL,
  path = here("output/"),
  scale = 1,
  width = NA,
  height = NA,
  units = c("in", "cm", "mm", "px"),
  dpi = 300,
  limitsize = TRUE,
  bg = NULL
)

summary(apps_joined$avg_reply_time)
hist(apps_joined$avg_reply_time)
plot(apps_joined$avg_rating, apps_joined$avg_reply_time)
# higher ratings are correlated with longer reply times
plot(apps_joined$avg_rating, apps_joined$response_rate)
# response rate are low in general but it's not clear from this graph

# create rating interval
apps_joined <- apps_joined %>%
    mutate(rating_interval = cut(avg_rating, 
                               breaks = seq(0, 5, by = 1),
                               include.lowest = TRUE,
                               right = FALSE))
summary(apps_joined$rating_interval)

apps_joined <- apps_joined %>%
    mutate(rating_interval_05 = cut(avg_rating, 
                               breaks = seq(0, 5, by = 0.5),
                               include.lowest = TRUE,
                               right = FALSE))
summary(apps_joined$rating_interval_05)

# plotting response rate by rating interval
apps_joined %>%
  filter(!is.na(rating_interval)) %>%
    ggplot(aes(x = rating_interval, y = response_rate)) +
    geom_boxplot(fill = "lightpink", outlier.alpha =  0.5) +
    theme_minimal() +
    labs(
        title = "Distribution of response rate by rating interval",
        x = "Rating interval",
        y = "Response rate"
    )
    # the mean response rate for apps in the 4-5 rating range
    # is lower than every other range but the 1-2 one
    # so replying is not associated with higher ratings

# Since there no data on the number of download
# we can use the number of reviews as a proxy for number of downloads


## ---- Distribution of days since update
summary(apps_joined$days_since_update)

# for apps with at least one review
summary(apps_joined$days_since_update[apps_joined$number_of_ratings > 0])

# correlation with ratings
apps_joined %>%
    filter(!is.na(rating_interval)) %>%
    ggplot(aes(x = rating_interval, y = days_since_update)) +
    geom_boxplot(fill = "lightgreen", outlier.alpha =  0.5) +
    theme_minimal() +
    labs(
        title = "Update Frequency and Apps' ratings",
        x = "Rating interval",
        y = "Days since last update"
    )
    # more frequent updates are associated with higher ratings

ggsave(
  "boxplot.png",
  plot = get_last_plot(),
  device = NULL,
  path = here("output/"),
  scale = 1,
  width = NA,
  height = NA,
  units = c("in", "cm", "mm", "px"),
  dpi = 300,
  limitsize = TRUE,
  bg = NULL
)

## ---- Market competition
# rating vs competition
apps_comp <- apps_joined %>%
    left_join(category_competition, by = "id_macro")

summary(apps_comp$n_apps)
hist(apps_comp$n_apps)

ggplot(apps_comp, aes(x = n_apps)) +
  geom_histogram(fill="#69b3a2", color="#e9ecef", alpha=0.9) +
  theme_minimal() +
  labs(
    title = "Distribution of Apps per Category",
    x = "Number of apps per category"
    ) +
  geom_vline(aes(xintercept=mean(n_apps)),
          color="lightpink", linetype="dashed")

ggsave(
  "app_category.png",
  plot = get_last_plot(),
  device = NULL,
  path = here("output/"),
  scale = 1,
  width = NA,
  height = NA,
  units = c("in", "cm", "mm", "px"),
  dpi = 300,
  limitsize = TRUE,
  bg = NULL
)

# create competition categories
# based on quartiles
apps_comp <- apps_comp %>%
    mutate(competition_category = ntile(n_apps, 4),
           competition_category = case_when(
            competition_category == 1 ~ "low competition",
            competition_category == 2 ~ "moderate competition",
            competition_category == 3 ~ "high competition",
            competition_category == 4 ~ "intense competition"
         ))

# ordering them
apps_comp <- apps_comp %>%
  mutate(competition_category = fct_relevel(competition_category, 
                                            "low competition", 
                                            "moderate competition", 
                                            "high competition", 
                                            "intense competition"))

# plotting category competition against average rating
ggplot(apps_comp, aes(competition_category, avg_rating)) +
  geom_boxplot() +
  theme_minimal() +
  labs(title = "App Ratings by Competition Level")
# The box plot may not be too clear and direct

# summary of rating ad success score
summary_cat <- apps_comp %>%
  group_by(competition_category) %>%
  summarize(
    mean_rating = mean(avg_rating, na.rm = TRUE),
    sd_rating = sd(avg_rating, na.rm = TRUE),
    mean_success_score = mean(success_score, na.rm = TRUE),
    sd_succ_score = sd(success_score, na.rm = TRUE),
    n = n()
  ) %>%
  mutate(se_rating = sd_rating / sqrt(n),
         se_success = sd_succ_score / sqrt(n)
  )

# bar plot for rating
ggplot(summary_cat, 
       aes(x = competition_category, y = mean_rating, fill = competition_category)
       ) +
  geom_col(alpha = 0.8) +
  geom_errorbar(aes(ymin = mean_rating - se_rating,
                    ymax = mean_rating + se_rating
                    ), width = 0.2) +
  theme_minimal() +
  labs(title = "Average Rating by Competition Level",
       subtitle = "Error bars represent Standard Error")
    # Intense competition has the lowest average rating
    # this could indicate that there are simply more apps but
    # that it's not very competitive since some app may not have many reviews

# bar plot for success score
ggplot(summary_cat, 
       aes(x = competition_category, y = mean_success_score, fill = competition_category)
       ) +
  geom_col(alpha = 0.8) +
  geom_errorbar(
    aes(ymin = mean_success_score - se_success,
        ymax = mean_success_score + se_success
        ), width = 0.2) +
  theme_minimal() +
  labs(title = "Average Success Score by Competition Level",
       subtitle = "Error bars represent Standard Error")

# Distribution of the categories
tabyl(apps_comp, n_apps, competition_category)
  # there are apps that share the same category concentration but
  # belongs into two different competition category
  # so I create new groups to address this issue
apps_comp <- apps_comp %>%
    mutate(competition_category2 = case_when(
            n_apps <= 152   ~ "low competition",
            n_apps <= 319   ~ "moderate competition",
            n_apps <= 730   ~ "high competition",  
            n_apps >= 1491   ~ "intense competition"
         ))

# ordering them
apps_comp <- apps_comp %>%
  mutate(competition_category2 = fct_relevel(competition_category2, 
                                            "low competition", 
                                            "moderate competition", 
                                            "high competition", 
                                            "intense competition"))

# summary of rating ad success score
summary_cat2 <- apps_comp %>%
  group_by(competition_category2) %>%
  summarize(
    mean_rating = mean(avg_rating, na.rm = TRUE),
    sd_rating = sd(avg_rating, na.rm = TRUE),
    mean_success_score = mean(success_score, na.rm = TRUE),
    sd_succ_score = sd(success_score, na.rm = TRUE),
    n = n()
  ) %>%
  mutate(se_rating = sd_rating / sqrt(n),
         se_success = sd_succ_score / sqrt(n)
  )

# bar plot for success score
ggplot(summary_cat2, 
       aes(x = competition_category2, y = mean_success_score, fill = competition_category2)
       ) +
  geom_col(alpha = 0.8) +
  geom_errorbar(
    aes(ymin = mean_success_score - se_success,
        ymax = mean_success_score + se_success
        ), width = 0.2) +
  theme_minimal() +
  labs(title = "Average Success Score by Competition Level",
       subtitle = "Error bars represent Standard Error")

## Merging key benefits and see vs market competition
apps_comp <- apps_comp %>%
    left_join(benefits, by = "app_id")

summary_comp <- apps_comp %>%
  group_by(competition_category) %>%
  summarize(
    mean_benefits = mean(number_of_benefits, na.rm = TRUE),
    sd = sd(number_of_benefits, na.rm = TRUE),
    n = n()
  ) %>%
  mutate(se = sd / sqrt(n)
  )

ggplot(summary_comp, 
       aes(x = competition_category, y = mean_benefits, fill = competition_category)
       ) +
  geom_col(alpha = 0.8) +
  geom_errorbar(
    aes(ymin = mean_benefits - se,
        ymax = mean_benefits + se
        ), width = 0.2) +
  theme_minimal() +
  labs(title = "Average Number of Features per Competition Category",
       subtitle = "Error bars represent Standard Error")

## ---- Average monthly fee
summary(apps_billings$monthly_price)
# there are outliers that heavily skew the mean
hist(apps_billings$price_numeric)

apps_billings %>%
  filter(monthly_price <= 2000) %>%
  ggplot(aes(x =monthly_price)) +
  geom_histogram()

# Average monthly fee by macro category
price_cateogry <- apps_billings %>%
  group_by(macro_category) %>%
  summarize(
    average_price = mean(monthly_price, na.rm = TRUE),
    median_price = median(monthly_price, na.rm = TRUE),
    total = n()
  )

print(price_cateogry)

# Average monthly fee by number of plans
price_plan <- apps_billings %>%
  group_by(number_of_plans) %>%
  summarize(
    average_price = mean(monthly_price, na.rm = TRUE),
    median_price = median(monthly_price, na.rm = TRUE),
    total = n()
  ) %>%
  drop_na()


print(price_plan)

# Graph of median price per number of plans
ggplot(price_plan,
    aes(x = number_of_plans, y = median_price, fill = factor(number_of_plans))
    ) +
    geom_bar(stat = "identity") +
    scale_fill_brewer(palette = "Pastel2") +
    theme_minimal()


# Average monthly fee per rating interval
price_rating <- apps_billings %>%
    #create internal
  mutate(rating_interval = cut(avg_rating, 
                               breaks = seq(0, 5, by = 1),
                               include.lowest = TRUE,
                               right = FALSE)) %>%
    #group by interval
  group_by(rating_interval) %>%
  summarize(
    average_price = mean(monthly_price, na.rm = TRUE),
    median_price = median(monthly_price, na.rm = TRUE),
    total = n()
  )

print(price_rating)

# 1. Reshape the data from wide to long
price_rating_long <- price_rating %>%
  pivot_longer(
    cols = c(average_price, median_price), 
    names_to = "price_metric", 
    values_to = "price_value"
  )

# 2. Plot 
ggplot(price_rating_long,
  aes(x = rating_interval, y = price_value, fill = price_metric)
  ) +
  geom_text(aes(label = price_value), vjust = 1.6, color = "white", size = 3.5) +
  geom_col(position = "dodge") +
  scale_fill_manual(
            values = c("average_price" = "#1b9e77", "median_price" = "#d95f02"),
            labels = c("Average Price", "Median Price")
            ) +
  labs(
    title = "Comparison of Average and Median Price by Rating",
    x = "Rating Interval",
    y = "Price ($)",
    fill = "Metric"
  ) +
  theme_minimal()


# Average monthly fee per app group
monthly_summary <- data.frame(
    group = c("Subscription", "Freemium", "One-time"),
    mean_fee = c(mean(subs_apps$app_price_monthly, na.rm = TRUE),
                 mean(freemium$app_price_monthly, na.rm = TRUE),
                 mean(one_time_app$app_price_numeric, na.rm = TRUE))
)
View(monthly_summary)

# Average monthly fee per app group
month_group <- apps_comp %>%
  mutate(group = case_when(
    has_free_plan == 0 ~ "subscription",
    has_free_plan == 1 ~ "freemium"
  )) %>%
  group_by(rating_interval, group) %>%
  summarise(
    average_price = mean(app_price_monthly, na.rm = TRUE),
    median_price = median(app_price_monthly, na.rm = TRUE),
    total = n()
  )

# Average
month_group %>%
  drop_na(rating_interval, group) %>%
ggplot(
  aes(x = rating_interval, y = average_price, fill = group)
  ) +
  geom_text(
    aes(label = round(average_price, 2)), 
    position = position_dodge(width = 0.9),
    vjust = -1, color = "black", size = 3.5) +
  geom_col(position = "dodge") +
  labs(
    title = "Average Price by Rating Interval and Pricing Strategy",
    x = "Rating Interval",
    y = "Average Monthly Price ($)",
    fill = "Pricing group"
  ) +
  theme_minimal()

ggsave(
  "avg_price.png",
  plot = get_last_plot(),
  device = NULL,
  path = here("output/"),
  scale = 1,
  width = NA,
  height = NA,
  units = c("in", "cm", "mm", "px"),
  dpi = 300,
  limitsize = TRUE,
  bg = NULL
)

# Median
month_group %>%
  drop_na(rating_interval, group) %>%
ggplot(
  aes(x = rating_interval, y = median_price, fill = group)
  ) +
  geom_text(
    aes(label = round(median_price, 2)), 
    position = position_dodge(width = 0.9),
    vjust = -1, color = "black", size = 3.5) +
  geom_col(position = "dodge") +
  labs(
    title = "Median Price by Rating Interval and Pricing Strategy",
    x = "Rating Interval",
    y = "Median Monthly Price ($)",
    fill = "Pricing group"
  ) +
  theme_minimal()

ggsave(
  "mediang_price.png",
  plot = get_last_plot(),
  device = NULL,
  path = here("output/"),
  scale = 1,
  width = NA,
  height = NA,
  units = c("in", "cm", "mm", "px"),
  dpi = 300,
  limitsize = TRUE,
  bg = NULL
)

#############
### 5. Exporting data ----
save(
    apps_joined,
    apps_macro,
    category_competition,
    free_apps,
    freemium,
    subs_apps,
    apps_billings,
    benefits,
    apps_comp,
    file = "data/processed/modelling_bundle.RData"
)

saveRDS(reviews_edited, file = "data/processed/sentiment_reviews.rds")