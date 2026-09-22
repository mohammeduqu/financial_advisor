class InvoiceError(Exception):
    """Safe, stable API errors; never include model output or invoice content."""

    def __init__(self, code, message, status=422):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status
