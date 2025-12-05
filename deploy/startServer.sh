#!/bin/bash
set -euo pipefail

echo "Starting server..."

python3 -m venv venv
source venv/bin/activate

pip install --upgrade pip
pip install -r requirements.txt

python3 app.py