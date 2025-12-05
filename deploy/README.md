# Solt Script Deployment Server

A lightweight Flask-based webhook server that handles automated deployments from GitHub for the Meerby Laravel multi-tenant application.

## Overview

This deployment server listens for GitHub webhook events and automatically:
1. Pulls the latest code from the `run-script` branch
2. Gracefully restarts itself to apply any updates to the deployment server

**⚠️ Important:** When a deployment is triggered, the server will shut itself down after returning a 200 response. This allows the deployment server itself to be updated. We recommend using a service manager (like systemd) to automatically restart it.

## Features

- 🔐 HMAC signature verification for GitHub webhooks
- 📦 Automatic git pull from Production branch
- 🔄 Multi-tenant Docker container restart
- 🔁 Self-updating capability
- 📝 Detailed deployment logging
- 📧 Email reporting for deployment status

## Prerequisites

- Python 3.7+
- Git
- Docker and Docker Compose
- Access to the repository
- SMTP server for email notifications (optional)

## Installation

1. **Clone or navigate to the deploy directory:**
   ```bash
   cd /home/pc-scripts/Meerby-Solt-Receiver-Beacons/deploy
   ```

2. **Copy the environment template:**
   ```bash
   cp .env.example .env
   ```

3. **Configure your environment:**
   Edit `.env` and set:
   ```bash
   HMAC_SECRET=your_github_webhook_secret
   PORT=9002
   ```
   
   > 💡 The HMAC secret should match the secret configured in your GitHub webhook settings.

4. **Make the startup script executable:**
   ```bash
   chmod +x startServer.sh
   ```

## Quick Start

### Manual Start
```bash
./startServer.sh
```

The server will:
- Create a Python virtual environment
- Install dependencies from `requirements.txt`
- Start the Flask server on the configured port (default: 9002)

### Recommended: Setup as System Service

For production use, create a systemd service to automatically start and restart the deployment server.

**Create the service file:**
```bash
sudo nano /etc/systemd/system/solt-receiver-deploy.service
```

**Add the following configuration:**
```ini
[Unit]
Description=Meerby Laravel Deployment Server
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=your_username
WorkingDirectory=/path/to/Meerby Laravel/deploy
ExecStart=/path/to/Meerby Laravel/deploy/startServer.sh
Restart=always
RestartSec=5
StandardOutput=append:/path/to/Meerby Laravel/deploy/deploy.log
StandardError=append:/path/to/Meerby Laravel/deploy/deploy.log

# Environment
Environment="PATH=/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
```

**Enable and start the service:**
```bash
# Reload systemd to recognize the new service
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable solt-receiver-deploy.service

# Start the service
sudo systemctl start solt-receiver-deploy.service

# Check status
sudo systemctl status solt-receiver-deploy.service
```

**Useful service commands:**
```bash
# View logs
sudo journalctl -u solt-receiver-deploy.service -f

# Restart the service
sudo systemctl restart solt-receiver-deploy.service

# Stop the service
sudo systemctl stop solt-receiver-deploy.service
```

## GitHub Webhook Configuration

1. Go to your GitHub repository settings
2. Navigate to **Settings → Webhooks → Add webhook**
3. Configure:
   - **Payload URL:** `http://your-server:9002/deploy`
   - **Content type:** `application/json`
   - **Secret:** Your HMAC_SECRET from `.env`
   - **Events:** Select "Just the push event"
   - **Active:** ✓ Checked

## API Endpoints

### `GET /`
Health check endpoint.

**Response:**
```
Meerby Laravel Deployment server is running.
```

### `POST /deploy`
Webhook endpoint for GitHub push events.

**Headers Required:**
- `X-Hub-Signature-256`: GitHub HMAC signature

**Behavior:**
1. Verifies the webhook signature (if enabled)
2. Checks if the push is to the `Production` branch
3. Pulls latest code with `git pull origin Production`
4. Triggers `restartAllTenants.sh` in background
5. Returns 200 response
6. Shuts down server after 2 seconds (allowing service manager to restart it)

**Response:**
```json
{
  "status": "Started restarting all tenants"
}
```

## Deployment Scripts

The `scripts/` directory contains utility scripts that can be used individually or are called automatically during deployment:

### `restartAllTenants.sh`
Restarts all tenant Docker containers in the workspace.

**Usage:**
```bash
cd deploy
./scripts/restartAllTenants.sh [email_report]
```

**Parameters:**
- `email_report`: Optional. Set to `"true"` to email a restart report to developers

**Examples:**
```bash
# Basic restart without email
./scripts/restartAllTenants.sh

# Restart with email report
./scripts/restartAllTenants.sh true
```

**Behavior:**
- Scans parent directory for all `*.tenant` folders
- Skips `example.tenant`
- Stops and restarts each tenant's Docker containers
- Continues processing even if individual tenants fail
- Optionally sends an email report with stop/start status for each tenant

**Note:** Requires bash 3.2+ (compatible with macOS default bash)

### `startTenant.sh`
Starts a specific tenant's Docker containers.

**Usage:**
```bash
./scripts/startTenant.sh <tenant_dir>
```

**Example:**
```bash
./scripts/startTenant.sh ../dev.dcxs.cloud.tenant
```

**Behavior:**
- Converts tenant directory name to Docker Compose project name
- Starts containers using `docker-compose up -d`
- Uses tenant-specific `.env` file from the tenant directory

### `stopTenant.sh`
Stops a specific tenant's Docker containers.

**Usage:**
```bash
./scripts/stopTenant.sh <tenant_dir>
```

**Example:**
```bash
./scripts/stopTenant.sh ../ct457.meerby.com.tenant
```

**Behavior:**
- Converts tenant directory name to Docker Compose project name
- Gracefully stops all containers with `docker-compose down`

### Common Library (`libs/common.sh`)
Shared utility functions used by the scripts:

- `tenantDirToProjectName()`: Converts tenant directory paths to Docker project names
  - Example: `./example.tenant` → `example_tenant`

### Email Library (`libs/emailDevs.sh`)
Email notification utility for sending deployment reports to developers.

**Requirements:**
- Configured SMTP settings in environment
- Email addresses configured for development team

## Logging

All deployment events are logged to `deploy.log` with timestamps:

```bash
# View deployment logs
tail -f deploy.log

# View recent deployments
tail -n 100 deploy.log
```

**Log format:**
```
[2025-10-28 14:30:45] Deployment request received.
[2025-10-28 14:30:45] 📦 Received deployment request: {...}
[2025-10-28 14:30:45] ⬇️ Pulling latest changes...
[2025-10-28 14:30:47] 🚀 Starting deployment...
[2025-10-28 14:30:47] ⚰️ Shutting down deployment server...
```

## How It Works

### Deployment Flow

1. **GitHub Push** → Production branch updated
2. **Webhook Triggered** → GitHub sends POST to `/deploy`
3. **Signature Verified** → HMAC validation
4. **Git Pull** → Latest code fetched
5. **Tenants Restart** → All Docker containers restarted in background
6. **Response Sent** → 200 OK returned to GitHub
7. **Server Shutdown** → Deployment server kills itself after 2 seconds
8. **Auto Restart** → Service manager (systemd) restarts the server with new code

### Self-Updating Mechanism

The server's self-update works through these steps:

1. After responding to the webhook, a background thread is started
2. The thread waits 2 seconds (allowing the response to complete)
3. The server sends itself a SIGTERM signal
4. The systemd service (with `Restart=always`) detects the shutdown
5. Systemd automatically restarts the server with the updated code

This ensures the deployment server itself can be updated through the same deployment process.

## Troubleshooting

### Server won't start
```bash
# Check Python version
python3 --version

# Manually create venv and test
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python3 app.py
```

### Deployments not triggering
1. Check GitHub webhook delivery status in GitHub settings
2. Verify HMAC_SECRET matches GitHub configuration
3. Check firewall/port accessibility
4. Review `deploy.log` for errors

### Tenants not restarting
```bash
# Test tenant scripts manually
./scripts/restartAllTenants.sh

# Check Docker status
docker ps -a

# Test individual tenant
./scripts/stopTenant.sh ../example.tenant
./scripts/startTenant.sh ../example.tenant
```

### Service not restarting
```bash
# Check service status
sudo systemctl status meerby-deploy.service

# View service logs
sudo journalctl -u meerby-deploy.service -n 50

# Verify Restart policy
sudo systemctl show meerby-deploy.service | grep Restart
```

### Bash compatibility issues (macOS)
The scripts are compatible with bash 3.2+ (default on macOS). If you encounter bash-related errors:

```bash
# Check bash version
bash --version

# Ensure scripts are executable
chmod +x scripts/*.sh
chmod +x scripts/libs/*.sh
```

## Security Considerations

- ✅ Always use HMAC signature verification in production
- ✅ Restrict webhook access with firewall rules
- ✅ Use HTTPS for webhook endpoints (configure reverse proxy)
- ✅ Limit server user permissions
- ✅ Keep the HMAC_SECRET secure (use Bitwarden note: Meerby-Deployment-HMAC-Secret)
- ✅ Secure email credentials if using email reporting feature

## Dependencies

See `requirements.txt` for full list:
- Flask 3.1.2 - Web framework
- python-dotenv 1.2.1 - Environment configuration
- gunicorn 23.0.0 - Production WSGI server (optional)

## License

Part of the Meerby Laravel multi-tenant application system.

---

**Maintained by:** Zodiac Group Toronto  
**Repository:** [Meerby-Rest-API](https://github.com/ZodiacGroupToronto/Meerby-Rest-API)