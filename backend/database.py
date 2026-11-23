
import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# Find the .env file beside database.py
env_path = Path(__file__).resolve().parent / ".env"
load_dotenv(dotenv_path=env_path, override=True)

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL environment variable is missing")

# Remote DB: a new connection costs ~3s, so keep enough alive for the ~10
# parallel requests a screen fires (overflow connections are closed after use).
engine = create_engine(DATABASE_URL, pool_recycle=240, pool_size=12, max_overflow=4)

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine
)

Base = declarative_base()
