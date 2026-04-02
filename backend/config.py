from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    # PostgreSQL
    DATABASE_URL: str = "postgresql://postgres.lrgjntwdntwqjnewarmk:Naveeeen2026@aws-1-ap-northeast-2.pooler.supabase.com:6543/postgres"

    # JWT
    SECRET_KEY: str = "your-secret-key-change-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440

    # Supabase Storage
    SUPABASE_URL: str = "https://lrgjntwdntwqjnewarmk.supabase.co"
    SUPABASE_ANON_KEY: str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxyZ2pudHdkbnR3cWpuZXdhcm1rIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQxNjM5MDMsImV4cCI6MjA4OTczOTkwM30.iWychRvPOaUEX-NUaW-Ofbxoo7qwihoraS0kytoaSgc"
    SUPABASE_SERVICE_KEY: str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxyZ2pudHdkbnR3cWpuZXdhcm1rIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NDE2MzkwMywiZXhwIjoyMDg5NzM5OTAzfQ.3_gwJiIh0o4BmnOjRKzyvpIBzCQ1TnjVs8PXwBT0t-Q"
    SUPABASE_BUCKET: str = "media"

    # Encryption
    MASTER_ENCRYPTION_KEY: str = "7f65ce720975d0ea198bb6d656005b59762ac51dd4aa414f16363640061b72e4"

    # Razorpay (optional)
    RAZORPAY_KEY_ID: Optional[str] = None
    RAZORPAY_KEY_SECRET: Optional[str] = None

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
    }


settings = Settings()
