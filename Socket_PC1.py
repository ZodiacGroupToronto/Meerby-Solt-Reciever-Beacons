import requests
import json
import serial
import serial.tools.list_ports
import time
import datetime
import multiprocessing
from multiprocessing import Process, Queue
from queue import Empty 
import logging
from websockets.sync.client import connect
import os
from dotenv import load_dotenv
import uuid
import threading
import win32crypt
from logging.handlers import TimedRotatingFileHandler
load_dotenv()

# #Check env variables
# required_env_vars = ['PASSPHRASE', 'STORE_BASE_URL', 'WS_URL']
# missing_vars = [var for var in required_env_vars if var not in os.environ]
# if missing_vars:
#     raise EnvironmentError(f"Missing required environment variables: {', '.join(missing_vars)}")


# Configure logging
LOG_DIR = r"C:\ProgramData\MeerbyPCScript\logs"
LOG_FILE = os.path.join(LOG_DIR, "app.log")

os.makedirs(LOG_DIR, exist_ok=True)

file_handler = TimedRotatingFileHandler(
    LOG_FILE,
    when="midnight",     # rotate daily
    interval=1,
    backupCount=30       # keep 30 days
)

formatter = logging.Formatter(
    '%(asctime)s - %(levelname)s - %(processName)s - %(message)s'
)

file_handler.setFormatter(formatter)

console_handler = logging.StreamHandler()
console_handler.setFormatter(formatter)

logging.basicConfig(
    level=logging.INFO,
    handlers=[file_handler, console_handler]
)

logger = logging.getLogger(__name__)


# ACK tracking
acks = Queue()

SECRETS_PATH = r"C:\ProgramData\MeerbyPCScript\secrets\secrets.bin"

_config_cache = None

def load_config():
    global _config_cache

    if _config_cache is None:
        with open(SECRETS_PATH, "rb") as f:
            encrypted = f.read()

        decrypted = win32crypt.CryptUnprotectData(encrypted, None, None, None, 0)[1]
        _config_cache = json.loads(decrypted.decode())
        required_env_vars = ['PASSPHRASE', 'STORE_BASE_URL', 'WS_URL', 'SOLT_RECIVER_SERIAL_ID']
        missing_vars = [var for var in required_env_vars if var not in _config_cache]
        if missing_vars:
            write_to_log(f"Error: Missing required environment variables in secrets file: {', '.join(missing_vars)}")
            raise EnvironmentError(f"Missing required environment variables: {', '.join(missing_vars)}")

    return _config_cache


def get_credentials(name: str):
    return load_config().get(name)


# Thread to handle incoming messages
def receiver(ws):
    while True:
        try:
            raw = ws.recv()
            msg = json.loads(raw)
            if msg.get("type") == "ack":
                server_id = msg.get("id")
                if server_id:
                    acks.put(server_id) 
            else:
                pass
        except Exception as e:
            write_to_log(f"Receiver stopped: {e}")
            break

def write_to_log(message: str) -> None:
    """Log messages to file and console with timestamp."""
    logger.info(message)

def get_reciever_token() -> str:
    #send to endpoint, get token
    password = get_credentials('PASSPHRASE')
    login_url = get_credentials('STORE_BASE_URL') + '/wp-json/api/os_authorization'
    payload = {'password': password}
    
    while True:
        try:
            response = requests.post(login_url, json=payload)
            response.raise_for_status()
            data = response.json()
            if data.get('status') == 200:
                write_to_log("Token Received")
                return data['jwt']
            write_to_log("Wrong Password when retrieving Token")
            time.sleep(3)
        except Exception as e:
            write_to_log(f"Retrying to Receive Token: retrying in 3 sec .... Error: {e}")
            time.sleep(3)

def get_reciever_serial_port() -> serial.Serial:
     #check if device is plugged
    comPort = ""
    while comPort == "":
        ports = list(serial.tools.list_ports.comports())
        write_to_log("List of serial Numbers found:")
        for port in ports:
            write_to_log(f"---- {port.serial_number}")
            if port.serial_number == get_credentials('SOLT_RECIVER_SERIAL_ID'):
                comPort = port.device
                write_to_log(f"Receiver found on {comPort}")
        if comPort == "":
            write_to_log("Warning: Solt Device Not found. Please make sure it is plugged in")
            time.sleep(3)
    
    try:
        serialPort = serial.Serial(port=comPort, baudrate=9600, bytesize=8, timeout=1, stopbits=serial.STOPBITS_ONE)
        return serialPort
    except serial.SerialException as e:
        write_to_log(f"Serial port error: {e}")
        raise

def producer(queue: Queue, token: str) -> None:
    """Read beacon events from serial port and push to queue."""
    write_to_log(f"Producer: Queue created")

    """In TEST_MODE generate fake beacon presses; otherwise read from serial."""
    test_mode = get_credentials("TEST_MODE") == "1"

    while True:
        try:
            receiverPort = get_reciever_serial_port()
            event = {'action': 'receiver_connected'}
            queue.put(event)
            write_to_log("Producer started, reading from serial port")
            while True:
                try:
                    if test_mode:
                            time.sleep(5)  # Simulate delay between presses
                            print("TEST MODE: Generating fake beacon press")
                            beaconId = "AAABBB"  # Example test ID
                            event = {'jwt': token, 'action': 'beacon_press', 'beacon_id': beaconId}
                            queue.put(event)

                    if receiverPort.in_waiting > 0:
                        serialString = receiverPort.readline()
                        beaconId = str(serialString[4:10]).replace("b", "").replace("'", "")
                        
                        if beaconId:
                            event = {'jwt': token, 'action': 'beacon_press', 'beacon_id': beaconId}
                            queue.put(event)
                            write_to_log(f"Produced event: {beaconId}")
                except serial.SerialException as e:
                    write_to_log(f"Serial error: {e}")
                    receiverPort.close()

                    #Let the consumer know we lost connection
                    event = {'action': 'receiver_disconnected'}
                    queue.put(event)
                    break  # Reconnect to serial port
                except Exception as e:
                    write_to_log(f"Unexpected error in producer: {e}")
                    time.sleep(1)
    
        except Exception as e:
            write_to_log(f"Producer failed to initialize: {e}")
            time.sleep(3)

def consumer(queue: Queue, websocket_url: str) -> None:
    """Send events over WebSocket. On send/registration failure: get a new token, re-register, and retry the event once"""
    """Consume events from queue and send over WebSocket."""
    """Waits for producer to start connection to websocket"""

    write_to_log(f"Consumer: Queue created")
    try:
        if not isinstance(queue, multiprocessing.queues.Queue):
            raise ValueError(f"Consumer: Expected multiprocessing.queues.Queue, got {type(queue)}")
    except ValueError as e:
        write_to_log(f"Consumer initialization error: {e}")
        return

    ping_interval = 15  # seconds

    receiver_is_connected = False
    websocket = None
    last_ping_time = time.time()

    while True:
        if receiver_is_connected and websocket is None:
            time.sleep(1)

            try:
                websocket = connect(websocket_url)
                write_to_log("Consumer: WebSocket connection established")
            except Exception as e:
                write_to_log(f"Consumer: WebSocket connection failed: {e}. Retrying in 3 seconds...")
                time.sleep(3)
                continue

            # Start each connection with a fresh token
            token = get_reciever_token()
            register_receiver(websocket, token)

            write_to_log("Consumer registered receiver")

            continue
        
        if websocket:
            # Send periodic pings to prevent keepalive timeouts
            if time.time() - last_ping_time > ping_interval:
                try:
                    websocket.pong()
                    #write_to_log("Sent WebSocket ping")
                    last_ping_time = time.time()
                except Exception as e:
                    write_to_log(f"Ping failed: {e}")
                    websocket.close()
                    websocket = None
        
        event = None
        try:
            event = queue.get(timeout=1)  # Non-blocking with timeout
            print(f"Consumer: processing event {event['action']}")
            print(f"receiver_is_connected: {receiver_is_connected} ")
        except Empty:
            continue

        if event['action'] == 'receiver_connected':
            receiver_is_connected = True
            write_to_log("Consumer: Receiver connected event received")

        elif event['action'] == 'receiver_disconnected':
            receiver_is_connected = False
            write_to_log("Consumer: Receiver disconnected event received")
            websocket.close()
            websocket = None
        elif receiver_is_connected:
            # try:
                # threading.Thread(target=receiver, args=(websocket,), daemon=True).start()
            try:
                # Overwrite any stale jwt from producer with the fresh one for THIS connection
                event_to_send = dict(event)
                event_to_send['jwt'] = token
                # Add unique ackId for tracking
                ack_id = str(uuid.uuid4())
                event_to_send['ackId'] = str(ack_id)

                websocket.send(json.dumps(event_to_send))
                send_ts = time.time()
                write_to_log(f"Sent event: {event_to_send['beacon_id']}, ID={event_to_send['ackId']}")

                # Wait for ACK with timeout
                # t0 = time.time()
                # while time.time() - t0 < 0.5:  # 500ms
                #     try:
                #         server_id = acks.get_nowait()
                #         write_to_log(f"ACK received: {server_id}")
                #         break
                #     except Empty:
                #         time.sleep(0.01)

            except Empty:
                continue  # Keep connection alive
            except Exception as e:
                write_to_log(f"Error sending event: {e}")
                websocket.close()
                websocket=None
                    
            # except Exception as e:
            #     write_to_log(f"WebSocket error: {e}. Reconnecting in 3 seconds...")
            #     time.sleep(3)

def register_receiver(websocket, token: str) -> None:
    """Send receiver registration message."""
    message = {'jwt': token, 'action': 'receiver_registration'}
    websocket.send(json.dumps(message))
    write_to_log("Receiver registered")

def main():
    websocket_url = get_credentials('WS_URL')
    token = get_reciever_token()
    
    # Create shared queue
    event_queue = multiprocessing.Queue()
    write_to_log(f"Main: Queue created")
    
    # Start producer and consumer processes
    producer_proc = Process(target=producer, args=(event_queue, token), name="Producer")
    consumer_proc = Process(target=consumer, args=(event_queue, websocket_url), name="Consumer")
    
    try:
        producer_proc.start()
        consumer_proc.start()
        producer_proc.join()
        consumer_proc.join()
    except KeyboardInterrupt:
        write_to_log("Shutting down...")
        producer_proc.terminate()
        consumer_proc.terminate()

if __name__ == "__main__":
    main()