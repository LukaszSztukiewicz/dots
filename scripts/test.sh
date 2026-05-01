#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info()  { echo "[smoke-test] $*"; }

info "Building smoke-test Docker image..."

docker build -t dots-smoke-test -f - "$REPO_ROOT" << 'DOCKERFILE'
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y curl python3 unzip git && rm -rf /var/lib/apt/lists/*

RUN sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin

RUN useradd -m -s /bin/bash testuser
USER testuser
WORKDIR /home/testuser
DOCKERFILE

info "Running smoke test in container..."

docker run --rm \
    -v "$REPO_ROOT:/dots:ro" \
    dots-smoke-test \
    bash -c '
set -euo pipefail

mkdir -p ~/bin
cat > ~/bin/bw << '"'"'BWEOF'"'"'
#!/usr/bin/env bash
# Stub bw for smoke testing
case "$*" in
  "status")
    echo '"'"'{"status":"unlocked"}'"'"'
    ;;
  "get item dots-git-secrets")
    echo '"'"'{"id":"test","name":"dots-git-secrets","fields":[{"name":"credential_helper","value":"store","type":0}]}'"'"'
    ;;
  *)
    echo "stub bw: unhandled args: $*" >&2
    exit 1
    ;;
esac
BWEOF
chmod +x ~/bin/bw
export PATH=~/bin:$PATH

mkdir -p ~/.config/chezmoi
cat > ~/.config/chezmoi/chezmoi.toml << EOF
sourceDir = "/dots/home"

[data]
  machineRole = "workstation"
  gitName     = "Smoke Test User"
  gitEmail    = "smoke@test.com"
  proxy       = ""
EOF

chezmoi apply --exclude=scripts

assert_file() {
    [ -f "$1" ] || { echo "FAIL: expected file $1"; exit 1; }
    echo "PASS: $1 exists"
}

assert_contains() {
    grep -q "$2" "$1" || { echo "FAIL: $1 does not contain: $2"; exit 1; }
    echo "PASS: $1 contains: $2"
}

assert_file ~/.gitconfig
assert_file ~/.zshrc
assert_file ~/.config/nvim/init.lua
assert_file ~/.config/tmux/tmux.conf

assert_contains ~/.gitconfig "Smoke Test User"
assert_contains ~/.gitconfig "smoke@test.com"
assert_contains ~/.gitconfig "helper = store"
assert_contains ~/.zshrc "cap()"

echo ""
echo "All smoke tests passed."
'

info "Smoke test complete."
