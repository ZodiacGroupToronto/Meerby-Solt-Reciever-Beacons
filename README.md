## Environment Setup
Create a .env file using the .env.example file.

(Optional) Verify Python 3.11+ is installed. If the path differs, edit PYTHON_EXE inside `scripts/update_and_restart.bat`.

## Task Scheduler Setup
1. Open Task Scheduler > Import Task.
2. Select the XML in the repo: `Meerby-Solt(Updater&KeepAlive).xml`.
3. In the General tab: Click "Change User or Group" > Advanced > Find Now > select your Windows user (often just the account name) > OK > OK.

After saving, a folder `MeerbyUpdater` will appear on the Desktop once the task runs (created by the script on first execution).

## Logs & State
Desktop folder: `MeerbyUpdater`
- `deploy.log`  All deployment & health‑check entries.
- `last_deployed_commit.txt`  The last applied commit hash from `release`.
- `meerby_update_runner.bat`  Temp self‑copy used during hard resets (may appear).
- In repo root: `app.pid` stores running Python process ID.

## How This Repo Works
The scheduled task runs `scripts/update_and_restart.bat` every 5 minutes.
Workflow each run:
1. `git fetch origin release`.
2. Compare local HEAD vs `origin/release`.
3. If different: hard reset to remote, install/refresh venv deps, kill running app process (PID from `app.pid`), restart `Socket_PC1.py` under the venv, record new commit hash.
4. If same: ensure the Python app is still running; if not, start it.
5. Log everything to `deploy.log`.

Remote watched: https://github.com/ZodiacGroupToronto/Meerby-Solt-Reciever-Beacons.git (branch `release`).

## File Reference
- `scripts/update_and_restart.bat`  Updater + keep‑alive script.
- `Meerby-Solt(Updater&KeepAlive).xml`  Preconfigured Task Scheduler definition.
- `Socket_PC1.py`  Main application script started by the updater.
- `requirements.txt`  Python dependencies installed into the venv.

## Manual Run
You can manually force a run by double‑clicking the scheduled task in Task Scheduler or executing the batch file from a command prompt.

## Troubleshooting
- No `MeerbyUpdater` folder: task hasn’t executed yet—run it manually.
- App not restarting: check `deploy.log` for pip/venv or git errors.
- Credential / permission errors: re‑open task > General > ensure correct user and privileges.cd

- auto update 3
