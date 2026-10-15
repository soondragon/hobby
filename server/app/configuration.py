from dataclasses import dataclass
import os
from urllib.parse import urlsplit


@dataclass(frozen=True, slots=True)
class Configuration:
    supabase_url: str
    publishable_key: str

    @classmethod
    def from_environment(cls) -> "Configuration":
        origin = os.environ.get("SUPABASE_URL", "").rstrip("/")
        key = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")
        parsed = urlsplit(origin)
        if (parsed.scheme != "https" or not (parsed.hostname or "").endswith(".supabase.co")
                or parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment
                or parsed.port not in (None, 443) or not key or len(key) > 4096):
            raise ValueError("Cloud service configuration is incomplete")
        # Only a publishable/legacy anon key belongs here. Never deploy a service-role key.
        if key.startswith("sb_secret_"):
            raise ValueError("A public publishable key is required")
        if key.count(".") == 2:
            import base64
            import json
            try:
                encoded = key.split(".")[1]
                role = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))["role"]
            except (ValueError, KeyError, TypeError):
                raise ValueError("Invalid legacy public key") from None
            if role != "anon":
                raise ValueError("A public publishable key is required")
        return cls(origin, key)
