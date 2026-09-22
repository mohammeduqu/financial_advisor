"""Retired seller lookup: opening a result must not consume another search credit."""
from services.errors import InvoiceError

DISABLED_MESSAGE = (
    "Open the product link from the search results; extra store lookups are "
    "disabled to save search credits."
)


def resolve_shop_link(shopping, body):
    """Compatibility entry point; deliberately never accesses provider or cache."""
    raise InvoiceError("shop_lookup_disabled", DISABLED_MESSAGE, 410)
