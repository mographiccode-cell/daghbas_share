from dataclasses import dataclass
import os


@dataclass(frozen=True)
class Settings:
    app_name: str = os.getenv("APP_NAME", "Daghbas Share API")
    app_version: str = os.getenv("APP_VERSION", "0.2.0")
    database_url: str = os.getenv("DATABASE_URL", "sqlite:///./daghbas_share.db")
    secret_key: str = os.getenv("SECRET_KEY", "dev-secret-key-change-me")
    algorithm: str = os.getenv("JWT_ALGORITHM", "HS256")
    access_expire_min: int = int(os.getenv("ACCESS_EXPIRE_MIN", "15"))
    refresh_expire_days: int = int(os.getenv("REFRESH_EXPIRE_DAYS", "7"))
    installation_master_key: str = os.getenv("INSTALLATION_MASTER_KEY", "change-me-master-key")
    license_secret: str = os.getenv("LICENSE_SECRET", "change-me-license-secret")


settings = Settings()
