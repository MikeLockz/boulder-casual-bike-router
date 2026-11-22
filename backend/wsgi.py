"""One production worker owns both routing graphs; requests use worker threads."""
from app import app, start_graph_initialization

start_graph_initialization()
