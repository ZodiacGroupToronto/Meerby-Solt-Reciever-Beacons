import json
import win32crypt
import os

# if arguments are not provided, show an error message
print("Set environment variables for PASSPHRASE, STORE_BASE_URL, WS_URL and SOLT_RECIVER_SERIAL_ID before running the script.")

CRYPTPROTECT_LOCAL_MACHINE = 0x4
data = {
    "PASSPHRASE": os.getenv("PASSPHRASE", "passphrase"),
    "STORE_BASE_URL": os.getenv("STORE_BASE_URL", "https://example.meerby.com"),
    "WS_URL": os.getenv("WS_URL", "wss://example.meerby.com/ws"),
    "SOLT_RECIVER_SERIAL_ID": os.getenv("SOLT_RECIVER_SERIAL_ID", "1234567")
}

encrypted = win32crypt.CryptProtectData(
    json.dumps(data).encode(),
    None, None, None, None,
    CRYPTPROTECT_LOCAL_MACHINE
)

with open(r"C:\ProgramData\MeerbyPCScript\secrets\secrets.bin", "wb") as f:
    f.write(encrypted)