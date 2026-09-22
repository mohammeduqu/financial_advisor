"""Origins for local Flutter browser development, including random debug ports."""
import re
from urllib.parse import urlsplit

# Flutter chooses a new browser port on each VS Code debug launch.
_PORT = r"(?:[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])"
LOOPBACK_ORIGIN = re.compile(
    r"\Ahttps?://(?:localhost|127\.0\.0\.1|\[::1\])(?::" + _PORT + r")?\Z",
    re.IGNORECASE,
)


def allowed_origin_patterns(configured):
    patterns = [LOOPBACK_ORIGIN]
    for origin in configured.split(","):
        origin = origin.strip()
        if not origin:
            continue
        try:
            parsed = urlsplit(origin)
            valid = (
                parsed.scheme in {"http", "https"} and parsed.hostname
                and not parsed.username and not parsed.password
                and not parsed.path and not parsed.query and not parsed.fragment
                and not any(c.isspace() for c in origin) and "*" not in origin
                and (parsed.port is None or 1 <= parsed.port <= 65535)
                and origin == parsed.geturl()
            )
        except ValueError:
            valid = False
        if not valid:
            raise ValueError("NUMO_ALLOWED_ORIGINS must contain explicit HTTP(S) origins.")
        patterns.append(re.compile(r"\A" + re.escape(origin) + r"\Z"))
    return patterns


def origin_is_allowed(origin, patterns):
    return any(pattern.fullmatch(origin) for pattern in patterns)
