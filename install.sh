#!/usr/bin/env bash
# sf-agent-installer
#
# Installs the shared baseline that every 5GL AI agent assumes is in place:
#   - Anthropic API key persisted in ~/.5gl-agents-env (sourced from ~/.zshrc)
#   - Xcode Command Line Tools
#   - Homebrew
#   - Salesforce CLI (sf), Python 3.12, git
#
# Each agent installs separately (clone its repo, run its setup.sh).
# macOS only. Idempotent — safe to re-run.

set -euo pipefail

KEY_FILE="$HOME/.5gl-agents-env"
ZSHRC="$HOME/.zshrc"
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

# ---------- failure banner (printed via trap on any non-zero exit) ----------
print_failure_banner() {
  cat >&2 <<EOF

${RED}${BOLD}==================================================================${RESET}
${RED}${BOLD}  INSTALLATION DID NOT FINISH${RESET}
${RED}${BOLD}==================================================================${RESET}

  The installer stopped during this step:

      ${BOLD}${CURRENT_STEP}${RESET}

  The specific reason is in the error message above. Most
  failures fall into one of these categories:

  ${BOLD}1) Anthropic API key rejected${RESET} (look for "HTTP 401" or "HTTP 403")
     Your key is wrong, expired, or revoked. Get a fresh one at
     https://console.anthropic.com/ and re-run this installer.
     Answer "n" when asked whether to use the existing key.

  ${BOLD}2) No internet${RESET} (look for "Could not reach api.anthropic.com")
     Check your wifi or ethernet, then re-run the installer.

  ${BOLD}3) Homebrew link conflict${RESET} (look for "brew link" / "already exists")
     A tool was already installed on your Mac outside of Homebrew.
     Run this for whichever package brew complained about, then
     re-run the installer:
         brew uninstall --ignore-dependencies <package-name>

  ${BOLD}4) Xcode Command Line Tools dialog canceled${RESET}
     Re-run the installer and click "Install" when the Apple
     system dialog appears.

  ${BOLD}Re-running this installer is safe.${RESET} It will skip every step
  that already finished and try again at the one that failed.
  Nothing on your Mac is broken.

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

# ---------- 1. macOS check ----------
step "Checking platform"
if [ "$(uname)" != "Darwin" ]; then
  err "sf-agent-installer is macOS-only. Detected: $(uname)"
  exit 1
fi
ok "macOS detected."

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
# Managed by sf-agent-installer. Edit this file to rotate the key.
export FIVEGL_ANTHROPIC_API_KEY="$api_key"
EOF
chmod 600 "$KEY_FILE"
ok "Wrote $KEY_FILE (chmod 600)."

# ---------- 6. Source line in ~/.zshrc ----------
if [ -f "$ZSHRC" ] && grep -qF "$SOURCE_LINE" "$ZSHRC"; then
  ok "$ZSHRC already sources $KEY_FILE."
else
  printf '\n# Added by sf-agent-installer\n%s\n' "$SOURCE_LINE" >> "$ZSHRC"
  ok "Appended source line to $ZSHRC."
fi

# Make the key available for the rest of this script's session too.
export FIVEGL_ANTHROPIC_API_KEY="$api_key"

# ---------- 7. Xcode Command Line Tools ----------
step "Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
  ok "Already installed at $(xcode-select -p)."
else
  say "Triggering install (a system dialog will appear; accept and wait for it to finish)..."
  xcode-select --install || true
  until xcode-select -p >/dev/null 2>&1; do
    say "Waiting for Xcode CLT install to complete..."
    sleep 15
  done
  ok "Xcode Command Line Tools installed."
fi

# ---------- 8. Homebrew ----------
step "Homebrew"
if command -v brew >/dev/null 2>&1; then
  ok "Already installed: $(brew --version | head -1)"
else
  say "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  ok "Homebrew installed."
fi

# ---------- 9. brew packages ----------
# We check the binary is on PATH rather than asking brew "did you install it?".
# Many Salesforce admins install `sf` via the official Salesforce installer (not
# brew), and many Macs ship with a usable python3 / git already. If the binary
# is already callable, leave it alone — installing on top causes brew link
# conflicts (it refuses to overwrite files it didn't manage).
step "Salesforce CLI, Python 3, git"
check_or_install() {
  local cmd="$1"     # binary to look for on PATH
  local pkg="$2"     # brew formula to install if missing
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd already on PATH ($(command -v "$cmd"))."
  else
    say "Installing $pkg..."
    brew install "$pkg"
    ok "$pkg installed."
  fi
}
check_or_install sf       sf
check_or_install python3  python@3.12
check_or_install git      git

# ---------- 10. Success banner ----------
cat <<EOF

${GREEN}${BOLD}==================================================================${RESET}
${GREEN}${BOLD}  INSTALLATION COMPLETE${RESET}
${GREEN}${BOLD}==================================================================${RESET}

  Your Mac is now set up to run any 5GL AI agent. Specifically:

      ${GREEN}[ok]${RESET} Anthropic API key saved (in ~/.5gl-agents-env)
      ${GREEN}[ok]${RESET} Xcode Command Line Tools
      ${GREEN}[ok]${RESET} Homebrew
      ${GREEN}[ok]${RESET} Salesforce CLI (sf)
      ${GREEN}[ok]${RESET} Python 3
      ${GREEN}[ok]${RESET} git

  ${BOLD}Next step — install the agent you want to run.${RESET}

  For sf-initial-setup-agent, paste these commands one at a time
  into your Terminal:

      git clone https://github.com/5GL-ai/sf-initial-setup-agent.git \\
          ~/5gl-agents/sf-initial-setup-agent
      cd ~/5gl-agents/sf-initial-setup-agent
      ./setup.sh
      ./run.sh

  ${BOLD}IMPORTANT:${RESET} open a NEW Terminal window before running the
  agent (or in this same window first run:
  ${BOLD}source ~/.5gl-agents-env${RESET}). This makes your Mac aware of the
  API key you just saved.

  You can close this window now.

EOF
