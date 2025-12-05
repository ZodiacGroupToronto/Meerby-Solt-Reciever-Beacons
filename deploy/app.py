import os
import subprocess
import sys
import threading
import utils.HMAC as HMAC
from flask import Flask, request, jsonify
import time 
from datetime import datetime
from dotenv import load_dotenv
import signal

load_dotenv()

app = Flask(__name__)

environment = os.getenv("ENVIRONMENT", "run-script").lower()

@app.route('/')
def home():
    return f"Solt Receiver Deployment server is running in {environment} branch.", 200

@app.route('/deploy', methods=['POST'])
def deploy():
    signature_header = request.headers.get('X-Hub-Signature-256')

    if not signature_header:
        return jsonify({"status": "Missing X-Hub-Signature-256"}), 401

    body = request.data

    if not HMAC.verify(body, signature_header):
        return jsonify({"status": "Invalid X-Hub-Signature-256"}), 401

    log_deployment_event("Deployment request received.")
    data = request.get_json()

    branch = environment

    if data.get('ref') != f'refs/heads/{branch}':
        log_deployment_event(f"Deployment aborted: Not the {branch} branch.")
        return jsonify({"status": f"Ignored: Not the {branch} branch"}), 200
    log_deployment_event(f"Received deployment request: {data}")

    log_deployment_event("Pulling latest changes...")

    result = subprocess.run(["git", "pull", "origin", branch], stdout=open("deploy.log", "a"), stderr=subprocess.STDOUT)

    if result.returncode != 0:
        log_deployment_event(f"Git pull failed with return code {result.returncode}.")
        return jsonify({"status": "Git pull failed", "return_code": result.returncode}), 500

    log_deployment_event("Starting update...")
    
    return jsonify({"status": "Repository updated"}), 200

def shutdown_server():
    """Restart the Flask process after a short delay."""
    log_deployment_event("Shutting down deployment server...")

    # Kill the current process, which will cause the parent process manager to restart it
    # If running with gunicorn/systemd, this will trigger a restart
    os.kill(os.getpid(), signal.SIGTERM)

def log_deployment_event(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open("deploy.log", "a") as log_file:
        log_file.write(f"[{timestamp}] {message}\n")

if __name__ == '__main__':
    log_deployment_event("Starting deployment server...")
    app.run(host='0.0.0.0', port=os.getenv("PORT", 9000))