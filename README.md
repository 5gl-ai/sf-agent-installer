# sf-agent-installer

One-shot baseline installer for 5GL AI agents on **macOS** and **Windows**.
Each individual agent (`sf-initial-setup-agent`, `sf-data-export-agent`, etc.)
installs separately and assumes this baseline is already in place.

Linux as a first-class target is out of scope. (For deploying agents on EC2 /
Linux servers, see the separate `ec2-agent-installer` project.)

## What it installs

**On macOS:**
- Anthropic API key written to `~/.5gl-agents-env` (sourced from `~/.zshrc`)
- Xcode Command Line Tools
- Homebrew
- Salesforce CLI (`sf`), Python 3, git

**On Windows (via WSL):**
- Windows Subsystem for Linux + Ubuntu
- Anthropic API key written to `~/.5gl-agents-env` inside Ubuntu
  (sourced from `~/.bashrc`)
- git, Python 3, Node.js, Salesforce CLI (`sf`) — all inside the WSL Ubuntu
  environment

## Usage — macOS

```bash
git clone https://github.com/5GL-ai/sf-agent-installer.git
cd sf-agent-installer
./install.sh
```

You'll be prompted for an Anthropic API key first. The installer validates it
against the Anthropic API before installing anything else.

Re-running `install.sh` is safe — every step checks "is this already done?"
and skips.

## Usage — Windows

> **Windows support is experimental.** The script bootstraps WSL automatically
> if it isn't already installed; if anything goes sideways, see the manual
> fallback at the bottom of this section.

Windows doesn't ship with `git`, so the easiest way to get the installer onto
your machine is the GitHub ZIP:

1. In your browser, go to https://github.com/5gl-ai/sf-agent-installer
2. Click the green **"Code"** button → **"Download ZIP"**
3. Right-click the downloaded zip → **"Extract All..."**. Note the extracted
   folder path (typically
   `C:\Users\<you>\Downloads\sf-agent-installer-main\sf-agent-installer-main\`
   — GitHub nests the contents inside a folder of the same name).
4. Open **PowerShell as Administrator** (Start menu → right-click PowerShell →
   "Run as Administrator").
5. `cd` into the extracted folder, then run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```
   Windows blocks unsigned `.ps1` files by default; the `-ExecutionPolicy
   Bypass` flag is per-session and doesn't change system state.
6. If WSL isn't installed yet, the script will install it and ask you to
   reboot.
7. After reboot, Ubuntu opens automatically and asks for a Linux username /
   password. Set them — you'll need the password for `sudo` later.
8. Re-run the same command from step 5 (Admin PowerShell). This time it'll
   detect WSL is ready, prompt you for your Anthropic API key, and finish the
   install inside Ubuntu.

**Manual WSL fallback** (if `install.ps1` can't bootstrap WSL on your
machine — e.g., corporate group policy blocks it):

1. In an Admin PowerShell:  `wsl --install`
2. Reboot.
3. Open Start menu → Ubuntu, set a Linux username/password.
4. Re-run `.\install.ps1` — it'll detect WSL is now ready.

## Installing an agent after the baseline is in place

**macOS:**
```bash
git clone https://github.com/5GL-ai/sf-initial-setup-agent.git ~/5gl-agents/sf-initial-setup-agent
cd ~/5gl-agents/sf-initial-setup-agent
./setup.sh
./run.sh
```

Open a new terminal first (or `source ~/.5gl-agents-env`) so the API key is
loaded.

**Windows (inside Ubuntu via WSL):**

Open Start menu → Ubuntu, then:
```bash
git clone https://github.com/5GL-ai/sf-initial-setup-agent.git ~/5gl-agents/sf-initial-setup-agent
cd ~/5gl-agents/sf-initial-setup-agent
./setup.sh
./run.sh
```

Open a new Ubuntu shell first (or `source ~/.5gl-agents-env`) so the API key
is loaded.

## What this installer does NOT do

- Does not clone or install individual agents — each agent's repo has its own
  `setup.sh`.
- Does not authenticate to Salesforce — each agent handles `sf org login`
  itself.
- Does not deploy agents to AWS / EC2 — that's a separate project
  (`ec2-agent-installer`).

## Requirements

- **macOS** (Apple silicon or Intel) **or** Windows 10 build 19041+ / Windows 11
- An Anthropic API key — https://console.anthropic.com/

## Re-running

Both `install.sh` and `install.ps1` are idempotent. Re-running them is the
recommended way to recover from a partial / failed install — every step
checks "is this already done?" and skips.
