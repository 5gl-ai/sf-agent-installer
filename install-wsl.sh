#!/usr/bin/env bash
# install-wsl.sh
#
# WSL/Ubuntu install path for sf-agent-installer.
#
# This script is called by install.ps1 from a Windows host. It is NOT meant to
# be run directly on bare Linux — bare Linux is explicitly out of scope for
# sf-agent-installer (see the 2026-05-02 scope decision in the master log).
#
# Steps:
#   1. Verify we're in WSL/Linux
#   2. Anthropic API key prompt + curl validation + write to ~/.5gl-agents-env
#   3. Append source line to ~/.bashrc
#   4. apt update + base packages (git, python3, curl)
#   5. Node.js (NodeSource) + Salesforce CLI (npm install -g @salesforce/cli)

set -euo pipefail

KEY_FILE="$HOME/.5gl-agents-env"
BASHRC="$HOME/.bashrc"
SOURCE_LINE='[ -f "$HOME/.5gl-agents-env" ] && source "$HOME/.5gl-agents-env"'

# ---------- output helpers ----------
if [ -t 1 ]; then
  BOLD=$(tput bold); RESET=$(tput sgr0)
  RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3)
else
  BOLD=""; RESET=""; RED=""; GREEN=""; YELLOW=""
fi

CURRENT_STEP="Starting installation"

say()  { printf "%s\n" "$*"; }
ok()   { printf "${GREEN}[ok]${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${RESET}  %s\n" "$*"; }
err()  { printf "${RED}[x]${RESET}  %s\n" "$*" >&2; }
step() { CURRENT_STEP="$*"; printf "\n${BOLD}==> %s${RESET}\n" "$*"; }

# ---------- failure banner ----------
print_failure_banner() {
  cat >&2 <<EOF

${RED}${BOLD}==================================================================${RESET}
${RED}${BOLD}  INSTALLATION DID NOT FINISH (inside WSL/Ubuntu)${RESET}
${RED}${BOLD}==================================================================${RESET}

  The installer stopped during this step:

      ${BOLD}${CURRENT_STEP}${RESET}

  The specific reason is in the error message above. Most failures
  fall into one of these categories:

  ${BOLD}1) Anthropic API key rejected${RESET} (look for "HTTP 401" or "HTTP 403")
     Your key is wrong, expired, or revoked. Get a fresh one at
     https://console.anthropic.com/ and re-run install.ps1.
     Answer "n" when asked whether to use the existing key.

  ${BOLD}2) No internet${RESET} (look for "Could not reach api.anthropic.com")
     Check your network, then re-run install.ps1.

  ${BOLD}3) sudo password${RESET} (look for "incorrect password" or sudo prompts)
     The Linux user inside Ubuntu needs a working sudo password.
     Set one with: passwd
     Then re-run install.ps1.

  ${BOLD}4) apt or npm download failure${RESET}
     Usually transient. Re-run install.ps1.

  ${BOLD}Re-running is safe.${RESET} Steps that already finished will skip.

EOF
}

on_exit() {
  local code=$?
  if [ -n "${resp_file:-}" ] && [ -f "${resp_file}" ]; then
    rm -f "$resp_file"
  fi
  if [ "$code" -ne 0 ]; then
    print_failure_banner
  fi
}
trap on_exit EXIT

# ---------- 1. Linux check ----------
step "Checking platform"
if [ "$(uname)" != "Linux" ]; then
  err "install-wsl.sh expects to run on Linux/WSL. Detected: $(uname)"
  err "On macOS, run install.sh instead."
  exit 1
fi
ok "Linux/WSL detected ($(uname -r))."

# ---------- 2. Detect existing key ----------
step "Anthropic API key"

existing_key=""
existing_source=""
if [ -n "${FIVEGL_ANTHROPIC_API_KEY:-}" ]; then
  existing_key="$FIVEGL_ANTHROPIC_API_KEY"
  existing_source="FIVEGL_ANTHROPIC_API_KEY env var"
elif [ -f "$KEY_FILE" ] && grep -q '^export FIVEGL_ANTHROPIC_API_KEY=' "$KEY_FILE" 2>/dev/null; then
  existing_key=$(grep '^export FIVEGL_ANTHROPIC_API_KEY=' "$KEY_FILE" | head -1 \
                 | sed -E 's/^export FIVEGL_ANTHROPIC_API_KEY="?([^"]*)"?$/\1/')
  existing_source="$KEY_FILE"
elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  existing_key="$ANTHROPIC_API_KEY"
  existing_source="ANTHROPIC_API_KEY env var (will be promoted to FIVEGL_ANTHROPIC_API_KEY)"
fi

api_key=""
if [ -n "$existing_key" ]; then
  say "Found existing key in: $existing_source"
  read -r -p "Use this key? [Y/n] " ans
  case "${ans:-Y}" in
    [Yy]*|"") api_key="$existing_key" ;;
    *) api_key="" ;;
  esac
fi

# ---------- 3. Prompt if needed ----------
if [ -z "$api_key" ]; then
  printf "Paste your Anthropic API key (input hidden): "
  read -rs api_key
  printf "\n"
  if [ -z "$api_key" ]; then
    err "No key provided. Aborting."
    exit 1
  fi
fi

# ---------- 4. Validate via curl ----------
say "Validating key against Anthropic API..."
resp_file=$(mktemp /tmp/5gl-key-check.XXXXXX)

http=$(curl -sS -o "$resp_file" -w "%{http_code}" \
  -X POST https://api.anthropic.com/v1/messages \
  -H "x-api-key: $api_key" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
  || echo "000")

case "$http" in
  200)
    ok "Key validated."
    ;;
  000)
    err "Could not reach api.anthropic.com. Check your internet connection."
    exit 1
    ;;
  *)
    err "Anthropic API returned HTTP $http. Response body:"
    cat "$resp_file" >&2
    printf "\n" >&2
    if [ "$http" = "401" ] || [ "$http" = "403" ]; then
      err "Likely cause: the key is revoked, expired, or for an account without API access."
      err "Get a fresh key at https://console.anthropic.com/ and re-run; answer 'n' to skip the existing key."
    fi
    exit 1
    ;;
esac

# ---------- 5. Write key file ----------
umask 077
cat > "$KEY_FILE" <<EOF
# Managed by sf-agent-installer (install-wsl.sh). Edit to rotate the key.
export FIVEGL_ANTHROPIC_API_KEY="$api_key"
EOF
chmod 600 "$KEY_FILE"
ok "Wrote $KEY_FILE (chmod 600)."

# ---------- 6. Source line in ~/.bashrc ----------
if [ -f "$BASHRC" ] && grep -qF "$SOURCE_LINE" "$BASHRC"; then
  ok "$BASHRC already sources $KEY_FILE."
else
  printf '\n# Added by sf-agent-installer\n%s\n' "$SOURCE_LINE" >> "$BASHRC"
  ok "Appended source line to $BASHRC."
fi

export FIVEGL_ANTHROPIC_API_KEY="$api_key"

# ---------- 7. sudo access ----------
step "sudo access"
if ! sudo -v; then
  err "sudo password required. Set one with 'passwd', then re-run install.ps1."
  exit 1
fi
ok "sudo authenticated."
# Refresh sudo timestamp in background so long apt steps don't re-prompt
( while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null ) &
sudo_keepalive_pid=$!
trap 'kill "$sudo_keepalive_pid" 2>/dev/null || true; on_exit' EXIT

# ---------- 8. apt base packages ----------
# wslu provides `wslview`, which agents shipping a local web UI use to launch
# the user's Windows-side default browser from inside WSL (per the
# 2026-05-02 local-web-UI decision in the master log).
step "Base packages (git, python3, curl, wslu)"
sudo apt-get update -y -qq
sudo apt-get install -y -qq git python3 python3-pip python3-venv curl ca-certificates gnupg wslu
ok "Base packages installed."

# ---------- 9. Node.js ----------
step "Node.js (for Salesforce CLI)"
if command -v node >/dev/null 2>&1; then
  ok "node already on PATH ($(node --version))."
else
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - >/dev/null
  sudo apt-get install -y -qq nodejs
  ok "node installed ($(node --version))."
fi

# ---------- 10. Salesforce CLI ----------
step "Salesforce CLI"
if command -v sf >/dev/null 2>&1; then
  ok "sf already on PATH ($(sf --version | head -1))."
else
  sudo npm install -g @salesforce/cli >/dev/null 2>&1
  ok "sf installed ($(sf --version | head -1))."
fi

# ---------- 11. Success banner ----------
cat <<EOF

${GREEN}${BOLD}==================================================================${RESET}
${GREEN}${BOLD}  INSTALLATION COMPLETE (Windows / WSL)${RESET}
${GREEN}${BOLD}==================================================================${RESET}

  Your WSL/Ubuntu environment is set up to run any 5GL AI agent:

      ${GREEN}[ok]${RESET} Anthropic API key saved (in ~/.5gl-agents-env, inside WSL)
      ${GREEN}[ok]${RESET} git, Python 3, curl
      ${GREEN}[ok]${RESET} Node.js
      ${GREEN}[ok]${RESET} Salesforce CLI (sf)

  ${BOLD}Next step — install the agent you want to run.${RESET}

  Open Ubuntu (Start menu → Ubuntu) and paste these commands one at
  a time:

      git clone https://github.com/5GL-ai/sf-initial-setup-agent.git \\
          ~/5gl-agents/sf-initial-setup-agent
      cd ~/5gl-agents/sf-initial-setup-agent
      ./setup.sh
      ./run.sh

  ${BOLD}IMPORTANT:${RESET} open a NEW Ubuntu shell first (or run:
  ${BOLD}source ~/.5gl-agents-env${RESET}) so the API key is loaded.

  You can close this PowerShell window now.

EOF
