"""Edit the target here, then restart Flask to switch the model server."""
from dataclasses import dataclass
from urllib.parse import urlsplit, urlunsplit


# Change only this line to "local" to use the local profile below.
ACTIVE_OLLAMA_TARGET = "runpod"

# Use the Ollama server's base URL. /api/chat is added automatically.
# The local URL is relative to the computer running Flask.
OLLAMA_TARGETS = {
    "runpod": {
        "base_url": "https://x95wve7xogsidc-11434.proxy.runpod.net",
        "model": "gemma4:12b",
        "think": False,
    },
    "local": {
        "base_url": "http://127.0.0.1:11434",
        "model": "qwen3-vl:4b-instruct",
        "think": None,
    },
}


def normalize_ollama_base_url(value):
    """Accept a server URL or a copied Ollama API URL without duplicating /api."""
    try:
        if not isinstance(value, str) or not value.strip():
            raise ValueError()
        value = value.strip()
        if any(character.isspace() or ord(character) < 32 for character in value):
            raise ValueError()
        parsed = urlsplit(value)
        if (parsed.scheme not in {"http", "https"} or not parsed.hostname
                or parsed.username is not None or parsed.password is not None
                or parsed.query or parsed.fragment):
            raise ValueError()
        # Accessing port validates malformed and out-of-range port values.
        if parsed.port is not None and parsed.port <= 0:
            raise ValueError()
        path = parsed.path.rstrip("/")
        for suffix in ("/api/tags", "/api/chat", "/api"):
            if path.endswith(suffix):
                path = path[:-len(suffix)]
                break
        return urlunsplit((parsed.scheme, parsed.netloc, path, "", ""))
    except (ValueError, TypeError):
        raise ValueError("Invalid Ollama URL in backend/ollama_config.py.") from None


@dataclass(frozen=True)
class OllamaConfig:
    base_url: str
    model: str
    think: bool | None = None

    def __post_init__(self):
        object.__setattr__(self, "base_url", normalize_ollama_base_url(self.base_url))
        if (not isinstance(self.model, str) or not self.model.strip()
                or any(character.isspace() for character in self.model.strip())):
            raise ValueError("Invalid Ollama model in backend/ollama_config.py.")
        object.__setattr__(self, "model", self.model.strip())
        if self.think is not None and not isinstance(self.think, bool):
            raise ValueError("Ollama think must be True, False or None.")

    @property
    def chat_url(self):
        return self.base_url + "/api/chat"


def get_ollama_config(target=None):
    target = ACTIVE_OLLAMA_TARGET if target is None else target
    if not isinstance(target, str) or target not in OLLAMA_TARGETS:
        raise ValueError("Choose runpod or local in backend/ollama_config.py.")
    return OllamaConfig(**OLLAMA_TARGETS[target])
