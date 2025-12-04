"""
HMAC verification utility for deployment requests.
This module provides functionality to verify HMAC signatures
of incoming requests to ensure authenticity.
"""

import hmac
import hashlib
import os


def verify(body, signature_header):
    signature = signature_header.split('sha256=')[1]

    SECRET = os.getenv("HMAC_SECRET")

    # Compute HMAC SHA256
    computed_hmac = hmac.new(SECRET.encode(), body, hashlib.sha256)
    computed_signature = computed_hmac.hexdigest()

    return hmac.compare_digest(computed_signature, signature)