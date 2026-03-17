######################################
# Project: Shopify App Market
# File name: 2.models
# date: 03-2026
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
library(modelsummary)
library(fixest)
library(randomForest)


###################
### 2. Loading data ----
load(here("data/processed", "modelling_bundle.RData"))

View(apps_comp)

# Adding app group variable
apps_comp <- apps_comp %>%
    mutate(app_group = case_when(
        is_free == 1 ~ "free",
        is_one_time == 1 ~ "one-time",
        is_one_time == 0 & is_free == 0 ~ "subscription"
    ))

tabyl(apps_comp, app_group)



#################
### 3. Correlation matrix ----
colnames(apps_comp)

cor_matrix <- apps_comp %>%
  select(free_to_install, has_free_trial, days_since_update,
         id_macro, avg_rating, number_of_ratings, avg_reply_time,
         response_rate, app_price_numeric, is_one_time, number_of_plans,
         is_free, has_multiple_plans, has_free_plan,
         n_apps, number_of_benefits) %>%
  cor(use = "pairwise.complete.obs")

View(cor_matrix)

View(apps_comp)


#################
### 4. Determinant of rating ----
# Common baseline variables
shared_controls <- "days_since_update + response_rate + has_multiple_plans + competition_category + number_of_benefits"

# model 1 - app group no price
rating1 <- paste("avg_rating ~ app_group +", shared_controls)
# model 2 - dummies & price
rating2 <- paste("avg_rating ~ is_free + is_one_time + app_price_numeric +", shared_controls)
# model 3 - app group & price
rating3 <- paste("avg_rating ~ app_group + app_price_numeric +", shared_controls)

# --- Linear Regressions (Baseline)
model_rating_general1 <- lm(as.formula(rating1), data = apps_comp)
model_rating_general2 <- lm(as.formula(rating2), data = apps_comp)
model_rating_general3 <- lm(as.formula(rating3), data = apps_comp)

# --- Fixed Effects (Macrocategory)
model_fe_general1 <- feols(
    as.formula(paste(rating1, "| macro_category")),
    data = apps_comp
)

model_fe_general2 <- feols(
    as.formula(paste(rating2, "| macro_category")),
     data = apps_comp
)

model_fe_general3 <- feols(
    as.formula(paste(rating3, "| macro_category")),
    data = apps_comp
)

# --- Robustness Checks (Macro + Developer)
model_ro_general1 <- feols(
    as.formula(paste(rating1, "| macro_category + developer")),
    data = apps_comp
)

model_ro_general2 <- feols(
    as.formula(paste(rating2, "| macro_category + developer")),
    data = apps_comp
)

model_ro_general3 <- feols(
    as.formula(paste(rating3, "| macro_category + developer")),
    data = apps_comp
)

## Comparing models
# LM models
lm4_models <- list(
  "LM 1" = model_rating_general1,
  "LM 2" = model_rating_general2,
  "LM 3" = model_rating_general3
)

modelsummary(lm4_models, stars = TRUE)
    # The adj R^2 is the same across all models
    # But both AIC and BIC are lower in the first model
    # And thus is preferable


# FE models
# To see if fe coefficient are sistematically different from 0
fitstat(model_fe_general1, "wald")
    # We reject the null hp on the fixed effects
    # thus it's worth using a fe model

fe4_models <- list(
  "FE 1" = model_fe_general1,
  "FE 2" = model_fe_general2,
  "FE 3" = model_fe_general3
)

modelsummary(fe4_models, stars = TRUE)
    # Once again the first model performs better
    # in AIC and BIC with the same explicative power of the others

## Robust vs FE
ro4_models <- list(
    "FE 1" = model_fe_general1,
    "RO 1" = model_ro_general1
)

modelsummary(ro4_models, stars = TRUE)

## Linear and FE - Subcriptions apps
# these models investigate pricing strategies more in depth
# Filter first
apps_sub <- apps_comp %>% 
  filter(app_group == "subscription")

# Linear model
model_lm_sub <- lm(
    avg_rating ~ days_since_update + response_rate +
                 app_price_monthly + number_of_plans +
                 competition_category + number_of_benefits +
                 has_free_trial + has_free_plan,
    data = apps_sub
)

summary(model_lm_sub)

# FE model
model_fe_sub <- feols(
    avg_rating ~ days_since_update + response_rate +
                 app_price_monthly + number_of_plans +
                 competition_category + number_of_benefits +
                 has_free_trial + has_free_plan | macro_category,
    data = apps_sub
)

summary(model_fe_sub)


#################
### 5. Determinant of Popularity ----
# the proxy for popolarity
# is the number of review as seen earlier
# however the correction should be done as follows log(number_of_rating + 1)

# model 1 - app group no price
numrating1 <- paste("log(number_of_ratings + 1) ~ app_group +", shared_controls)
# model 2 - dummies & price
numrating2 <- paste("log(number_of_ratings + 1) ~ is_free + is_one_time + app_price_numeric +", shared_controls)
# model 3 - app group & price
numrating3 <- paste("log(number_of_ratings + 1) ~ app_group + app_price_numeric +", shared_controls)

# --- Linear Regressions (Baseline)
model_numrating_1 <- lm(as.formula(numrating1), data = apps_comp)
model_numrating_2 <- lm(as.formula(numrating2), data = apps_comp)
model_numrating_3 <- lm(as.formula(numrating3), data = apps_comp)


# --- Fixed Effects (Macrocategory)
model_fe_rating1 <- feols(
    as.formula(paste(numrating1, "| macro_category")),
    data = apps_comp
)

model_fe_rating2 <- feols(
    as.formula(paste(numrating2, "| macro_category")),
     data = apps_comp
)

model_fe_rating3 <- feols(
    as.formula(paste(numrating3, "| macro_category")),
    data = apps_comp
)

# --- Robustness Checks (Macro + Developer)
model_ro_rating1 <- feols(
    as.formula(paste(numrating1, "| macro_category + developer")),
    data = apps_comp
)

model_ro_rating2 <- feols(
    as.formula(paste(numrating2, "| macro_category + developer")),
    data = apps_comp
)

model_ro_rating3 <- feols(
    as.formula(paste(numrating3, "| macro_category + developer")),
    data = apps_comp
)

## Comparing models
# LM models
lm5_models <- list(
  "LM 1" = model_numrating_1,
  "LM 2" = model_numrating_2,
  "LM 3" = model_numrating_3
)

modelsummary(lm5_models, stars = TRUE)
    # The adj R^2 is the same across all models
    # the AIC is slightly higher in the first model
    # and the BIC is slighly lower even though the
    # difference is small and not significative
    # And thus model 2 and 3 should be preferable


# FE models
# To see if fe coefficient are sistematically different from 0
fitstat(model_fe_rating1, "wald")
    # We reject the null hp on the fixed effects
    # thus it's worth using a fe model

fe5_models <- list(
  "FE 1" = model_fe_rating1,
  "FE 2" = model_fe_rating2,
  "FE 3" = model_fe_rating3
)

modelsummary(fe5_models, stars = TRUE)
    # The within R^2 is slighly higher for models 2 and 3
    # similarly they have lower AIC and higher BIC

## Robust vs FE
ro5_models <- list(
    "FE 1" = model_fe_rating1,
    "RO 1" = model_ro_rating1
)

modelsummary(ro5_models, stars = TRUE)

## Linear and FE - Subcriptions apps
# Linear model
model_lm_sub_nr <- lm(
    number_of_ratings ~ days_since_update + response_rate +
                 app_price_monthly + number_of_plans +
                 competition_category + number_of_benefits +
                 has_free_trial + has_free_plan,
    data = apps_sub
)

summary(model_lm_sub_nr)

# FE model
model_fe_sub_nr <- feols(
    number_of_ratings ~ days_since_update + response_rate +
                 app_price_monthly + number_of_plans +
                 competition_category + number_of_benefits +
                 has_free_trial + has_free_plan | macro_category,
    data = apps_sub
)

summary(model_fe_sub_nr)

#################
### 6. Determinant of Success ----
# model 1 - app group no price
succsore1 <- paste("success_score ~ app_group +", shared_controls)
# model 2 - dummies & price
succsore2 <- paste("success_score ~ is_free + is_one_time + app_price_numeric +", shared_controls)
# model 3 - app group & price
succsore3 <- paste("success_score ~ app_group + app_price_numeric +", shared_controls)

# --- Linear Regressions (Baseline)
model_succscore_1 <- lm(as.formula(succsore1), data = apps_comp)
model_succscore_2 <- lm(as.formula(succsore2), data = apps_comp)
model_succscore_3 <- lm(as.formula(succsore3), data = apps_comp)


# --- Fixed Effects (Macrocategory)
model_fe_succscore1 <- feols(
    as.formula(paste(succsore1, "| macro_category")),
    data = apps_comp
)

model_fe_succscore2 <- feols(
    as.formula(paste(succsore2, "| macro_category")),
     data = apps_comp
)

model_fe_succscore3 <- feols(
    as.formula(paste(succsore3, "| macro_category")),
    data = apps_comp
)

# --- Robustness Checks (Macro + Developer)
model_ro_succscore1 <- feols(
    as.formula(paste(succsore1, "| macro_category + developer")),
    data = apps_comp
)

model_ro_succscore2 <- feols(
    as.formula(paste(succsore2, "| macro_category + developer")),
    data = apps_comp
)

model_ro_succscore3 <- feols(
    as.formula(paste(succsore3, "| macro_category + developer")),
    data = apps_comp
)

## Comparing models
# LM models
lm6_models <- list(
  "LM 1" = model_succscore_1,
  "LM 2" = model_succscore_2,
  "LM 3" = model_succscore_3
)

modelsummary(lm6_models, stars = TRUE)
    # The adj R^2 is the same across all models
    # the AIC is slightly higher in the first model
    # and the BIC is slighly lower even though the
    # difference is small and not significative
    # And thus model 2 and 3 should be preferable


# FE models
# To see if fe coefficient are sistematically different from 0
fitstat(model_fe_succscore1, "wald")
    # We reject the null hp on the fixed effects
    # thus it's worth using a fe model

fe6_models <- list(
  "FE 1" = model_fe_succscore1,
  "FE 2" = model_fe_succscore2,
  "FE 3" = model_fe_succscore3
)

modelsummary(fe6_models, stars = TRUE)
    # The within R^2 is the same across all models
    # models 2 and 3 have lower AIC but higher BIC
    
## Robust vs FE
ro6_models <- list(
    "FE 1" = model_fe_succscore1,
    "RO 1" = model_ro_succscore1
)

modelsummary(ro6_models, stars = TRUE)

## Linear and FE - Subcriptions apps
# Linear model
model_lm_sub_ss <- lm(
    success_score ~ days_since_update + response_rate +
                 app_price_monthly + number_of_plans +
                 competition_category + number_of_benefits +
                 has_free_trial + has_free_plan,
    data = apps_sub
)

summary(model_lm_sub_ss)

# FE model
model_fe_sub_ss <- feols(
    success_score ~ days_since_update + response_rate +
                 app_price_monthly + number_of_plans +
                 competition_category + number_of_benefits +
                 has_free_trial + has_free_plan | macro_category,
    data = apps_sub
)

summary(model_fe_sub_ss)

#################
### 7. Printint Models ----
# To visualize lm all togheter
lm_models <- list(
    "Ratings" = model_rating_general1,
    "Popularity" = model_numrating_1,
    "Success Score" = model_succscore_1
)

modelsummary(lm_models, stars = TRUE)

# To visualize fe all togheter
fe_models <- list(
    "Ratings" = model_fe_general1,
    "Popularity" = model_fe_rating1,
    "Success Score" = model_fe_succscore1
)

modelsummary(fe_models, stars = TRUE)

# To visualize subcription models
sub_models <- list(
    "Ratings" = model_lm_sub,
    "Popularity" = model_lm_sub_nr,
    "Success Score" = model_lm_sub_ss
)

modelsummary(sub_models, stars = TRUE)

sub_fe_models <- list(
    "Ratings" = model_fe_sub,
    "Popularity" = model_fe_sub_nr,
    "Success Score" = model_fe_sub_ss
)

modelsummary(sub_fe_models, stars = TRUE)



#################
### 8. Variables Importance ----
# To determine the variable importance
# I fit a random forest

## 8.1 Splitting the datset

rf_dataset <- apps_comp %>%
    drop_na(avg_rating)

set.seed(123)

split <- sample(seq_len(nrow(rf_dataset)), 0.7 * nrow(rf_dataset))
train <- rf_dataset[split, ]
test  <- rf_dataset[-split, ]


## 8.2 Modelling
# ---- Rating
random_model <- "avg_rating ~ app_group + days_since_update + has_multiple_plans + competition_category + number_of_benefits"

rf_model <- randomForest(
    as.formula(random_model),
    data = train,
  ntree = 500,
  mtry = 2,
  na.action = na.omit,
  importance = TRUE
)

print(rf_model)

# ---- Popularity
random_model2 <- "number_of_ratings ~ app_group + days_since_update + has_multiple_plans + competition_category + number_of_benefits"

rf_model2 <- randomForest(
    as.formula(random_model2),
    data = train,
  ntree = 500,
  mtry = 2,
  na.action = na.omit,
  importance = TRUE
)


pred <- predict(rf_model, newdata = test)

# Confusion matrix
table(Predicted = pred, Original = test$avg_rating)

# Accuracy
mean(pred == test$avg_rating)

# Importance tables
importance(rf_model) # 1st model

importance(rf_model2) # 2nd model

# Plotting the importance table
varImpPlot(rf_model, main = "Variables importance") # ratings

varImpPlot(rf_model2, main = "Variables importance") # popularity


# More advanced graph
imp1 <- importance(rf_model)

imp_df1 <- data.frame(
    Variable = rownames(imp1),
    importance = imp1[, "%IncMSE"]
)

imp_df1 <- imp_df1 %>%
  mutate(Variable = recode(Variable,
    number_of_benefits = "Number of Features",
    days_since_update = "Days Since Last Update",
    competition_category = "Competition Level",
    has_multiple_plans = "Multiple Plans",
    app_group = "Price category"
  ))

imp_df1 <- imp_df1 %>%
    arrange(importance)

ggplot(imp_df1, aes(x = importance, y = reorder(Variable, importance))) +
  geom_col(fill = "#2C7FB8") +
  labs(
    title = "Key Drivers of Model Predictions",
    x = "Importance (% Increase in Prediction Error)",
    y = ""
  ) +
  theme_minimal(base_size = 14)

ggsave(
  "random_forest.png",
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

View(imp1)

### 9. Exporting data ----
save(
    shared_controls,
    rating1,
    numrating1,
    succsore1,
    model_fe_general1,
    model_fe_rating1,
    model_fe_succscore1,
    model_fe_sub,
    model_fe_sub_nr,
    model_fe_sub_ss,
    fe_models,
    model_fe_sub_ss,
    model_fe_sub_nr,
    model_fe_sub,
    sub_fe_models,
    imp1,
    imp_df1,
    file = "data/processed/model_summary_bundle.RData"
)
