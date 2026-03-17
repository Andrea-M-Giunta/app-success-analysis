#################################
#
# TEXT CLUSTERING FOR GROUPPING CATEGORIES
# Project: Shopify apps analysis
#
#################################

import pandas as pd
from sentence_transformers import SentenceTransformer
from sklearn.cluster import AgglomerativeClustering
from sklearn.cluster import KMeans
from sklearn.preprocessing import normalize
import numpy as np
import hdbscan
import re
from umap import UMAP
from bertopic import BERTopic
from sklearn.feature_extraction.text import CountVectorizer
from pathlib import Path


# 0. Paths and directory
BASE_DIR = Path(__file__).parent
INPUT_PATH = BASE_DIR / "data" / "raw" / "categories.csv"
OUTPUT_PATH = BASE_DIR / "data" / "processed" / "clustered_categories.csv"

# 1. Loading data
df = pd.read_csv(INPUT_PATH)
df.head()

# 2. Normalize titles
df['title'] = df['title'].str.replace('-', ' ', regex=False)
df['title'] = df['title'].str.replace('other', '', regex=False)

df['title'] = df['title'].str.lower().str.strip()
df.head()

# 3. Sentece Transformer model and semantic embeddings
model = SentenceTransformer('all-MiniLM-L12-v2') # The all-MiniLM-L12-v2 is a good comprise between speed and performance

embeddings = model.encode(df['title'].tolist()) # embedding the title column
print(embeddings.shape)

similarities = model.similarity(embeddings, embeddings) #Calculate the embedding similarities
print(similarities)

# 4. Clustering 
# I don't use the classic K-means clustering since I would have to arbitrarly set a fixed number of clusters (K)
# Instead, I try three different methods: Agglomeratrive Clustering, HDBSCAN, BERT.
#
# 4.1 Agglomerative Clustering 
embeddings_normalized = normalize(embeddings)
agg_clustering = AgglomerativeClustering(
    n_clusters=None, 
    distance_threshold=1.2,
    linkage='ward'
)
agg_clustering.fit(embeddings_normalized)
df['cluster_agglomerate'] = agg_clustering.labels_

agg_clustering_cosine = AgglomerativeClustering(
    n_clusters=None,
    metric="cosine",
    linkage="average",
    distance_threshold=0.4
)
agg_clustering_cosine.fit(embeddings_normalized)
df['cluster_agglomerate_cosine'] = agg_clustering_cosine.labels_

# 4.2 HDBSCAN
# Dimensionality reduction first
umap_model = UMAP(
    n_neighbors=15,
    n_components=5,
    metric='cosine'
)
reduced = umap_model.fit_transform(embeddings_normalized)

clusterer = hdbscan.HDBSCAN(
    metric='euclidean',
    min_cluster_size=5,
    cluster_selection_method='eom'
)

df["cluster_hdbscan"] = clusterer.fit_predict(reduced)


# 4.3 BERT
# Vectorization to extract key words
vectorizer_model = CountVectorizer(
    ngram_range=(1, 2),   
    stop_words=None,      
    min_df=2              
)

topic_model = BERTopic(
    embedding_model=model,
    umap_model=umap_model,
    hdbscan_model=clusterer,
    vectorizer_model=vectorizer_model,
    top_n_words=10,          
    verbose=True)

topics, probs = topic_model.fit_transform(df['title'].tolist(), embeddings)

# 5. Automatically assigning a name for each macro category
df['macro_category_agg'] = df.groupby('cluster_agglomerate')['title'].transform(lambda x: min(x, key=len))
print(df[['title', 'macro_category_agg']])

df['macro_category_agg1'] = df.groupby('cluster_agglomerate_cosine')['title'].transform(lambda x: min(x, key=len))
print(df[['title', 'macro_category_agg1']])

df['macro_category_hdbscan'] = df.groupby('cluster_hdbscan')['title'].transform(lambda x: min(x, key=len))
print(df[['title', 'macro_category_hdbscan']])

df['cluster_bertopic'] = topics

topic_info = topic_model.get_topic_info()
print(topic_info[['Topic', 'Name', 'Count']])  # Name is auto-generated from top keywords

# Map back to df
df['macro_bertopic'] = [topic_model.topic_labels_[t] for t in topics]
df.head()


# 5. Exporting to csv
df.to_csv(OUTPUT_PATH, index=False)
