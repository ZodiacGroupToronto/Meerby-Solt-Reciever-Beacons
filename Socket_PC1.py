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

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(processName)s - %(message)s',
    handlers=[
        logging.FileHandler(r"C:\Users\User\Desktop\pcLogs.txt"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

load_dotenv()

# ACK tracking
acks = {}

# Thread to handle incoming messages
def receiver(ws):
    while True:
        try:
            raw = ws.recv()
            msg = json.loads(raw)
            if msg.get("type") == "ack":
                acks[msg.get("id")] = True
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
    password = os.getenv('PASSPHRASE')
    url = os.getenv('MEERBY_LOGIN_URL')
    payload = {'password': password}
    
    while True:
        try:
            response = requests.post(url, json=payload)
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
            if port.serial_number == os.getenv('SOLT_RECIVER_SERIAL_ID'):
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
    test_mode = os.getenv("TEST_MODE", "0") == "1"

    if test_mode:
        write_to_log("Producer running in TEST_MODE: generating fake events")
        fake_ids = ["A1B2C3", "D4E5F6", "112233", "445566"]
        i = 0
        while True:
            beacon_id = fake_ids[i % len(fake_ids)]
            event = {"jwt": token, "action": "beacon_press", "beacon_id": beacon_id}
            queue.put(event)
            write_to_log(f"[TEST_MODE] Produced event: {beacon_id}")
            i += 1
            time.sleep(2)    
    else:
        while True:
            try:
                receiverPort = get_reciever_serial_port()
                write_to_log("Producer started, reading from serial port")
                while True:
                    try:
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
    write_to_log(f"Consumer: Queue created")
    try:
        if not isinstance(queue, multiprocessing.queues.Queue):
            raise ValueError(f"Consumer: Expected multiprocessing.queues.Queue, got {type(queue)}")
    except ValueError as e:
        write_to_log(f"Consumer initialization error: {e}")
        return

    ping_interval = 15  # seconds

    while True:
        try:
            with connect(websocket_url) as websocket:
                write_to_log("Connection Successful!")

                threading.Thread(target=receiver, args=(websocket,), daemon=True).start()

                # Start each connection with a fresh token
                token = get_reciever_token()
                register_receiver(websocket, token)
                write_to_log("Consumer registered receiver")

                last_ping_time = time.time()
                
                while True:
                    try:
                        # Send periodic pings to prevent keepalive timeouts
                        if time.time() - last_ping_time > ping_interval:
                            try:
                                websocket.ping()
                                #write_to_log("Sent WebSocket ping")
                                last_ping_time = time.time()
                            except Exception as e:
                                write_to_log(f"Ping failed: {e}")
                                break  # Break inner loop to trigger reconnect

                        # Process queued events
                        event = queue.get(timeout=1)  # Non-blocking with timeout

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
                        t0 = time.time()
                        while time.time() - t0 < 0.5:  # 500ms
                            if acks.pop(ack_id, None):
                                write_to_log(f"ACK received: {ack_id}")
                                break
                            time.sleep(0.01)

                    except Empty:
                        continue  # Keep connection alive
                    except Exception as e:
                        write_to_log(f"Error sending event or ping: {e}")
                        break  # Reconnect on error
        except Exception as e:
            write_to_log(f"WebSocket error: {e}. Reconnecting in 3 seconds...")
            time.sleep(3)

def register_receiver(websocket, token: str) -> None:
    """Send receiver registration message."""
    message = {'jwt': token, 'action': 'receiver_registration'}
    websocket.send(json.dumps(message))
    write_to_log("Receiver registered")

def main():
    websocket_url = os.getenv('WS_URL')
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