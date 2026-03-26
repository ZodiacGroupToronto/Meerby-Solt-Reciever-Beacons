import json
import os
import sys
import win32crypt

SECRETS_DIR  = r"C:\ProgramData\MeerbyPCScript\secrets"
PLAIN_FILE   = os.path.join(SECRETS_DIR, "secrets_plain.json")
BINARY_FILE  = os.path.join(SECRETS_DIR, "secrets.bin")

REQUIRED_KEYS = ["PASSPHRASE", "STORE_BASE_URL", "WS_URL"]
# SOLT_RECIVER_SERIAL_ID is optional at setup time (can be added later)


def main():
    # ------------------------------------------------------------------
    # 1. Read plaintext JSON
    # ------------------------------------------------------------------
    if not os.path.isfile(PLAIN_FILE):
        print(f"[encrypt_secrets] ERROR: plaintext file not found: {PLAIN_FILE}", file=sys.stderr)
        print("  setup.ps1 should have written this file before calling encrypt_secrets.py.", file=sys.stderr)
        sys.exit(1)

    try:
        with open(PLAIN_FILE, "r", encoding="utf-8") as f:
            secrets: dict = json.load(f)
    except json.JSONDecodeError as exc:
        print(f"[encrypt_secrets] ERROR: failed to parse {PLAIN_FILE}: {exc}", file=sys.stderr)
        _safe_delete(PLAIN_FILE)
        sys.exit(1)

    # ------------------------------------------------------------------
    # 2. Validate required keys
    # ------------------------------------------------------------------
    missing = [k for k in REQUIRED_KEYS if k not in secrets]
    if missing:
        print(f"[encrypt_secrets] ERROR: missing required keys: {missing}", file=sys.stderr)
        _safe_delete(PLAIN_FILE)
        sys.exit(1)

    # ------------------------------------------------------------------
    # 3. Encrypt with DPAPI (bound to current Windows user on this machine)
    # ------------------------------------------------------------------
    try:
        plaintext_bytes = json.dumps(secrets).encode("utf-8")
        # CryptProtectData returns (description, encrypted_bytes)
        encrypted: bytes = win32crypt.CryptProtectData(
            plaintext_bytes,
            "MeerbySecrets",   # description string (metadata only)
            None,              # optional entropy
            None,              # reserved
            None,              # prompt struct
            0                  # flags: 0 = user-scope (only THIS user on THIS machine can decrypt)
        )
    except Exception as exc:
        print(f"[encrypt_secrets] ERROR: DPAPI encryption failed: {exc}", file=sys.stderr)
        _safe_delete(PLAIN_FILE)
        sys.exit(1)

    # ------------------------------------------------------------------
    # 4. Write secrets.bin
    # ------------------------------------------------------------------
    try:
        os.makedirs(SECRETS_DIR, exist_ok=True)
        with open(BINARY_FILE, "wb") as f:
            f.write(encrypted)
        print(f"[encrypt_secrets] secrets.bin written to {BINARY_FILE}")
    except Exception as exc:
        print(f"[encrypt_secrets] ERROR: failed to write {BINARY_FILE}: {exc}", file=sys.stderr)
        _safe_delete(PLAIN_FILE)
        sys.exit(1)

    # ------------------------------------------------------------------
    # 5. Delete plaintext JSON — must not persist on disk
    # ------------------------------------------------------------------
    _safe_delete(PLAIN_FILE)
    print("[encrypt_secrets] Plaintext JSON deleted. Setup complete.")


def _safe_delete(path: str) -> None:
    """Delete a file, overwriting its content first to reduce recovery risk."""
    try:
        if os.path.isfile(path):
            # Overwrite with zeros before deleting (best-effort secure erase)
            size = os.path.getsize(path)
            with open(path, "r+b") as f:
                f.write(b"\x00" * size)
                f.flush()
                os.fsync(f.fileno())
            os.remove(path)
            print(f"[encrypt_secrets] Deleted: {path}")
    except Exception as exc:
        print(f"[encrypt_secrets] WARNING: could not delete {path}: {exc}", file=sys.stderr)
        print(f"  Please delete it manually!", file=sys.stderr)


if __name__ == "__main__":
    main()