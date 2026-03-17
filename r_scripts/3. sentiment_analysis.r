######################################
# Project: Shopify App Market
# File name: 3.sentiment_analysis
# date: 02-2026
# author: Andrea M. Giunta
#######################################

####################
### 1. Library ----
library(tidyverse)
library(stringr)
library(here)
library(janitor)
library(cld2)
library(sentimentr)

###################
### 2. Loading and cleaning ----
reviews_sent <- readRDS(here("data/processed", "sentiment_reviews.rds"))

## cleaning doby text
clean_reviews <- reviews_sent %>%
  mutate(text_clean = body %>%
    str_to_lower() %>%
    str_replace_all("http\\S+|www\\S+", "") %>% # Remove URLs
    str_replace_all("[^\x01-\x7F]", "") %>% # Remove non-ASCII
    str_replace_all("[[:punct:]]", "") %>% # Remove punctuation
    str_squish() # Remove extra spaces
  )

View(head(clean_reviews, 1000))

# Remove observations with no text
clean_reviews <- clean_reviews %>%
  mutate(text_clean = na_if(text_clean, "")) %>%
  drop_na(text_clean)


## Language detection
# sentiment analysis is langue specific
# I create a variable to detect the language and filtering then only those
# I use the cld2 package
# Alternatively one can use LLM API to translate the body
clean_lang <- clean_reviews %>%
  mutate(lang = detect_language(text_clean))

View(head(clean_lang, 1000))
# the model can't pick up a language if there are too few words

tabyl(clean_lang, lang)
# since there are still more than 900k english observations
# I won't worry for those english short sentece reviews non-converted

# Select only english
eng_clean <- clean_lang %>%
  mutate(developer_reply_posted_at = as.Date(developer_reply_posted_at)) %>%
  filter(lang == "en")

View(head(eng_clean, 1000))


### 3. Sentiment analysis
# using sentimentr

eng_clean %>%
  get_sentences() %>% # breaks text into sentenctes
  sentiment_by(text_clean, app_id) # groups analysis by app id

eng_clean %>%
  mutate(text_split = get_sentences(text_clean)) %>%
  sentiment_by(text_split, app_id)