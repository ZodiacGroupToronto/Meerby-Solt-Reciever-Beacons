## Environment Setup
Create a .env file with the following variables:

```
STORE_BASE_URL= <STORE_BASE_URL> # e.g., https://dev.dcxs.cloud , no trailing slash
WS_URL= <WEBSOCKET_URL>
PASSPHRASE= <PASSPHRASE>
SOLT_RECIVER_SERIAL_ID= <SOLT_RECIVER_SERIAL_ID>
TEST_MODE= <0 (for production) | 1 (for test in local PC)> 
```

## Installation
Install the required Python libraries using pip (might be missing in some environments - please update if necessary):

```
pip install -r requirements.txt
```