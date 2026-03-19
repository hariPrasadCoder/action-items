from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    anthropic_api_key: str
    supabase_url: str
    supabase_service_key: str

    jwt_secret: str
    jwt_algorithm: str = "HS256"
    jwt_expire_days: int = 365

    slack_client_id: str = ""
    slack_client_secret: str = ""
    slack_redirect_uri: str = "http://localhost:8000/slack/callback"

    google_client_id: str = ""
    google_client_secret: str = ""
    google_redirect_uri: str = "http://localhost:8000/gmail/callback"

    app_base_url: str = "http://localhost:8000"


settings = Settings()
