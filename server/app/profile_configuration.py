"""Server-only settings; the native application receives only the OAuth client ID."""
from dataclasses import dataclass
from pathlib import Path
import os
import re
from urllib.parse import urlsplit, parse_qs, urlencode, urlunsplit, quote


@dataclass(frozen=True, slots=True, repr=False)
class ProfileConfiguration:
    client_id: str
    client_secret: str
    database_url: str
    redirect_uri: str = 'hobbytrainer://auth/callback'

    @classmethod
    def from_environment(cls):
        value = cls(os.environ.get('GITHUB_PROFILE_CLIENT_ID', ''),
                    os.environ.get('GITHUB_PROFILE_CLIENT_SECRET', ''),
                    os.environ.get('TRAINER_DATABASE_URL', ''))
        parsed = urlsplit(value.database_url)
        if (not value.client_id or not value.client_secret or parsed.scheme not in ('postgresql', 'postgres')
                or not re.fullmatch(r'trainer_api(?:\.[a-z0-9]{20})?', parsed.username or '') or not parsed.password or not parsed.hostname
                or parse_qs(parsed.query).get('sslmode') != ['verify-full']):
            raise ValueError('Public-profile authentication configuration is incomplete')
        parameters = parse_qs(parsed.query)
        if parameters.get('sslrootcert') == ['bundled']:
            certificate = Path(__file__).resolve().parents[1] / 'certs' / 'supabase-root.crt'
            if not certificate.is_file():
                raise ValueError('Database trust certificate is missing')
            parameters['sslrootcert'] = [str(certificate)]
            database_url = urlunsplit(parsed._replace(query=urlencode(parameters, doseq=True, quote_via=quote)))
            return cls(value.client_id, value.client_secret, database_url)
        return value
