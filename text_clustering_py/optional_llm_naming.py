#################################
#
# TEXT CLUSTERING FOR GROUPPING CATEGORIES
# Project: Shopify apps analysis
#
#################################

import pandas as pd
import numpy as np
from pathlib import Path

# This code is optional
# It is used to derive more meaningfull macrocategory labels
# To avoid paying the API of an LLM model, I export a verion of 
# clustered_categories2.csv with one row per macrocategory
# to give it to a LLM chatbot. Then its response would be used
# to repmap the file

BASE_DIR = Path.cwd()
INPUT_PATH = BASE_DIR / "data" / "processed" / "clustered_categories2.csv"
OUTPUT_PATH = BASE_DIR / "data" / "processed" / "names_macrocategories.csv"

# 1. Loading data
df = pd.read_csv(INPUT_PATH)
df.head()

df = df[['id_macro', 'macro_category']] # keeps only id_macro and macro_category columns

df = df.sort_values('id_macro')


df_1 = df.drop_duplicates(subset=['macro_category'], keep='first') # keeps only one macro category
df_1.head()

df_1.to_csv(OUTPUT_PATH, index=False)
