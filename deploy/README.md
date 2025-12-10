# Solt Receiver - Deployment Server (Linux/systemd)

This repository folder contains a small Flask webhook server that automates deployments for the Meerby Laravel multi-tenant system. The server verifies GitHub HMAC signatures, pulls updated code, triggers tenant restarts, and then shuts down so a process manager (systemd) can restart it with the new code.

**This README** explains how to install, configure and run the deployment server on a Linux host using `systemd`, how to configure the GitHub webhook, how the restart/self-update flow works, and how to test and troubleshoot.

**Important:** The service intentionally shuts itself down after handling a deployment to allow the updated code to be loaded on restart. Use `systemd` with a restart policy (for example `Restart=always`).

**Files of interest:**
- `app.py`: Flask webhook server and deployment logic.
- `startServer.sh`: helper that creates a venv and starts the server.
- `requirements.txt`: Python dependencies.
- `.env.example`: environment variables template.
- `scripts/`: helper bash scripts (e.g., `pack_and_move.sh`).
- `utils/HMAC.py`: HMAC helper used to verify GitHub signatures.

**Assumptions:**
- You will run this on a Linux server (Ubuntu/Debian/CentOS compatible) with Python 3.8+ installed.
- You will use `systemd` to manage the service.
- The deployment repository is present on the same host and `git` is configured with appropriate credentials (SSH key or credential helper).

**Security note:** Use HTTPS and a firewall. Keep `HMAC_SECRET` private.

**Quick overview of the flow:**
- GitHub push to the Production branch → GitHub sends webhook to `/deploy` → Server verifies HMAC → `git pull` runs → local update script (e.g. `scripts/pack_and_move.sh`) runs to copy/build files into place → Server responds 200 and exits → `systemd` restarts server.

**Minimum prerequisites**
- Python 3.8+ (3.7 may work but newer is recommended)
- Git
- systemd

**Environment variables (in `.env`)**
- `HMAC_SECRET`: GitHub webhook secret (required for validation)
- `PORT`: port to listen on (default `9002`)
- Additional email/smtp variables may exist if email reporting is configured by your scripts.

**1) Install & Configure**

1. Put the deployment folder on the server, for example `/opt/meerby/solt-deploy` or `/home/deploy/solt-deploy`.

2. Copy the example env and edit it:

```bash
cd /opt/meerby/solt-deploy
cp .env.example .env
# edit .env and set HMAC_SECRET and PORT (and any SMTP settings)
nano .env
```

3. Make helper scripts executable:

```bash
chmod +x startServer.sh
chmod +x scripts/*.sh
```

4. Review `startServer.sh` to ensure it creates the virtualenv where you want it. The script provided in the repo will typically:
- create `venv/` inside the `deploy` folder
- `pip install -r requirements.txt`
- and run `python app.py` (or `gunicorn` if configured)

If you prefer to manage the venv manually:

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

**2) Create a `systemd` service**

Create `/etc/systemd/system/solt-receiver-deploy.service` with contents similar to the example below. Replace paths and `User` with your system values (use an unprivileged service user when possible):

```ini
[Unit]
Description=Meerby Solt Receiver Deployment Server

[Service]
Type=simple
User=root
WorkingDirectory=/home/dcxs/pc-scripts/Meerby-Solt-Reciever-Beacons/deploy
# Ensure ExecStart points to your start script or to the venv python run command
ExecStart=/home/dcxs/pc-scripts/Meerby-Solt-Reciever-Beacons/deploy/startServer.sh
Restart=always
RestartSec=5
# Send stdout/stderr to a log file (rotate with logrotate) or rely on journalctl
StandardOutput=append:/home/dcxs/pc-scripts/Meerby-Solt-Reciever-Beacons/deploy/deploy.log
StandardError=append:/home/dcxs/pc-scripts/Meerby-Solt-Reciever-Beacons/deploy/deploy.log
Environment="PATH=/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
```

Commands to enable and start the service:

```bash
# reload systemd after adding the unit file
sudo systemctl daemon-reload
sudo systemctl enable solt-receiver-deploy.service
sudo systemctl start solt-receiver-deploy.service
sudo systemctl status solt-receiver-deploy.service
```

If you prefer to run the `python` process directly without `startServer.sh`, change `ExecStart` to:

```ini
ExecStart=/opt/meerby/solt-deploy/venv/bin/python /opt/meerby/solt-deploy/app.py
```

**3) GitHub webhook configuration**

In GitHub repository settings → Webhooks → Add webhook:
- Payload URL: `http://YOUR_SERVER:9002/deploy` (use HTTPS behind a reverse proxy in production)
- Content type: `application/json`
- Secret: value of `HMAC_SECRET` set in `.env`
- Events: choose `Push` (or select only the Production branch if GitHub supports it in your repo)

The server expects the header `X-Hub-Signature-256` (HMAC-SHA256). The repo includes `utils/HMAC.py` to validate signatures.

Example: local test of signature generation (generate header for `curl` tests):

```bash
# prepare a small JSON payload file payload.json
PAYLOAD_FILE=payload.json
SECRET="your_secret_here"
SIG=$(python3 -c "import hmac,hashlib,sys,json; p=open('$PAYLOAD_FILE','rb').read(); print('sha256=' + hmac.new(b'$SECRET', p, hashlib.sha256).hexdigest())")
curl -H "X-Hub-Signature-256: $SIG" -H "Content-Type: application/json" --data-binary @$PAYLOAD_FILE http://localhost:9002/deploy
```

**4) How update & self-reload works**

- The webhook handler performs `git pull origin <branch>` (branch is configurable in `app.py` or your environment) to fetch new code.
- After the pull completes, the handler may run a local script from `scripts/` to move/build/copy updated files into the target folder. The repository includes `scripts/pack_and_move.sh` as an example.
- After returning a 200 response, the server starts a short timer (2s) and then exits (SIGTERM). `systemd` with `Restart=always` restarts the service, loading the updated code.

This design allows the deployment server to update itself and optionally run any custom commands needed to place code where your production system expects it.

**5) Logging & monitoring**

- Service logs via `journalctl -u solt-receiver-deploy.service -f`.
- If using `StandardOutput=append:/path/deploy.log` in the unit file, monitor that file with `tail -f /opt/meerby/solt-deploy/deploy.log`.
- Ensure `deploy.log` is writable by the service user and consider log rotation (`logrotate`).

**6) Testing & troubleshooting**

- Check Python/venv and dependencies:

```bash
python3 --version
cd /opt/meerby/solt-deploy
source venv/bin/activate
pip install -r requirements.txt
python app.py  # runs in foreground for quick debug
```

- Check webhook reception:

```bash
# from a remote machine (or GitHub), send a signed payload as shown above
curl -v -H "X-Hub-Signature-256: <signature>" -H "Content-Type: application/json" -d '{"ref":"refs/heads/Production"}' http://your-server:9002/deploy
```

- Check `deploy.log` and `journalctl` for errors.

Common checks:
- `sudo systemctl status solt-receiver-deploy.service`
- `sudo journalctl -u solt-receiver-deploy.service -n 200 --no-pager`
- Confirm `HMAC_SECRET` matches GitHub webhook secret.
- Confirm the server user has permission to run `git pull` and to run any post-deploy scripts (e.g., `scripts/pack_and_move.sh`).

**7) Permissions & security**

- Use a dedicated `deploy` user with limited permissions. The user must have read/write access to the deployment repo and ability to run the tenant scripts.
- If restart scripts call `docker-compose`, ensure the `deploy` user is in the `docker` group or use a controlled sudoers rule (limit sudo to the scripts needed).
- Serve the webhook over HTTPS (use a reverse proxy like nginx with TLS). Restrict inbound firewall rules to GitHub IPs where possible.

**8) Example `systemd` workflow commands**

```bash
# Reload units after edits
sudo systemctl daemon-reload

# Start/stop/restart
sudo systemctl start solt-receiver-deploy.service
sudo systemctl stop solt-receiver-deploy.service
sudo systemctl restart solt-receiver-deploy.service

# Watch logs
sudo journalctl -u solt-receiver-deploy.service -f
```

**9) Example troubleshooting scenarios**

- If `git pull` fails: inspect `deploy.log` or journal -> likely missing SSH key or permissions. Ensure the `deploy` user has the appropriate SSH key or credential helper.
- If post-deploy actions fail: run `./scripts/pack_and_move.sh` or other deploy scripts manually to see error output and verify paths/permissions.
- If webhook returns 401/403: verify signature header name and `HMAC_SECRET`.

**10) Optional: run behind Gunicorn + reverse proxy**

For higher concurrency or production hardening, run the Flask app under `gunicorn` and place nginx/nginx-proxy in front for TLS termination and request buffering. In that case, `ExecStart` should point to the gunicorn command using the `venv` python.

---

If you want, I can:
- add a `systemd` unit file template in this repo (e.g., `deploy/solt-receiver-deploy.service`),
- add a sample `logrotate` config for `deploy.log`, or
- create a small test script to exercise the webhook locally.

Tell me which of these you'd like me to add next.