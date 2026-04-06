#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2
  exit 1
}

require_root() {
  if [ "${EUID}" -ne 0 ]; then
    die "Run this script with sudo so it can install system packages and system-wide tools."
  fi
}

detect_target_user() {
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    printf '%s\n' "${SUDO_USER}"
    return 0
  fi

  die "Unable to determine the invoking user. Run the script via sudo from the target WSL user account."
}

is_wsl() {
  grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null
}

detect_ubuntu() {
  [ -r /etc/os-release ] || return 1
  # shellcheck disable=SC1091
  . /etc/os-release
  [ "${ID:-}" = "ubuntu" ] || [[ "${ID_LIKE:-}" == *ubuntu* ]]
}

run_as_user() {
  local cmd="$1"
  su - "${TARGET_USER}" -c "${cmd}"
}

apt_install_packages() {
  local packages=(
    build-essential
    ca-certificates
    curl
    gcc
    g++
    git
    jq
    make
    net-tools
    ripgrep
    telnet
    python3
    python3-pip
    unzip
    wget
  )

  log "Updating apt metadata"
  apt-get update

  log "Upgrading installed packages"
  apt-get -y upgrade

  log "Installing core development packages"
  apt-get install -y --no-install-recommends "${packages[@]}"
}

install_uv_if_missing() {
  if command -v uv >/dev/null 2>&1; then
    log "uv is already installed: $(uv --version)"
    return 0
  fi

  log "Installing uv system-wide"
  curl -fsSL https://astral.sh/uv/install.sh \
    | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh
}

install_managed_python_for_user() {
  log "Installing latest managed Python with uv for ${TARGET_USER}"
  run_as_user 'uv python install'
}

install_nvm_and_node_for_user() {
  log "Installing nvm and latest Node.js for ${TARGET_USER}"
  run_as_user '
    export NVM_DIR="$HOME/.nvm"
    export PROFILE="$HOME/.bashrc"
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    fi
    . "$NVM_DIR/nvm.sh"
    nvm install node
    nvm alias default node
  '
}

install_codex_for_user() {
  log "Installing OpenAI Codex CLI globally for ${TARGET_USER}"
  run_as_user '
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh"
    npm install -g @openai/codex@latest
  '
}

map_architecture_for_go() {
  case "$(dpkg --print-architecture)" in
    amd64) printf '%s\n' amd64 ;;
    arm64) printf '%s\n' arm64 ;;
    *)
      die "Unsupported architecture for Go: $(dpkg --print-architecture)"
      ;;
  esac
}

map_architecture_for_nvim() {
  case "$(dpkg --print-architecture)" in
    amd64) printf '%s\n' '(x86_64|64)' ;;
    arm64) printf '%s\n' 'arm64' ;;
    *)
      die "Unsupported architecture for Neovim: $(dpkg --print-architecture)"
      ;;
  esac
}

install_latest_go() {
  local go_arch go_url go_tarball

  go_arch="$(map_architecture_for_go)"
  go_url="$(
    curl -fsSL 'https://go.dev/dl/?mode=json' \
      | jq -r --arg arch "${go_arch}" '[.[] | select(.stable == true) | .files[] | select(.os == "linux" and .arch == $arch and .kind == "archive") | "https://go.dev/dl/" + .filename] | first'
  )"

  [ -n "${go_url}" ] && [ "${go_url}" != "null" ] || die "Failed to resolve the latest stable Go archive URL."

  log "Installing latest stable Go from ${go_url}"
  go_tarball="$(mktemp /tmp/go-latest.XXXXXX.tar.gz)"
  curl -fsSL "${go_url}" -o "${go_tarball}"

  rm -rf /usr/local/go
  tar -C /usr/local -xzf "${go_tarball}"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  rm -f "${go_tarball}"
}

install_latest_neovim() {
  local nvim_arch_pattern nvim_asset_url nvim_tarball nvim_extract_dir

  nvim_arch_pattern="$(map_architecture_for_nvim)"
  nvim_asset_url="$(
    curl -fsSL 'https://api.github.com/repos/neovim/neovim/releases/latest' \
      | jq -r --arg arch_pattern "${nvim_arch_pattern}" '[.assets[]?.browser_download_url | select(test("nvim-linux-" + $arch_pattern + "\\.tar\\.gz$"))] | first'
  )"

  [ -n "${nvim_asset_url}" ] && [ "${nvim_asset_url}" != "null" ] || die "Failed to resolve the latest stable Neovim archive URL."

  log "Installing latest stable Neovim from ${nvim_asset_url}"
  nvim_tarball="$(mktemp /tmp/nvim-latest.XXXXXX.tar.gz)"
  curl -fsSL "${nvim_asset_url}" -o "${nvim_tarball}"

  nvim_extract_dir="$(
    python3 - "${nvim_tarball}" <<'PY'
import sys
import tarfile

path = sys.argv[1]
with tarfile.open(path, 'r:gz') as tf:
    member = tf.getmembers()[0]
    print(member.name.split('/', 1)[0])
PY
  )"
  [ -n "${nvim_extract_dir}" ] || die "Failed to determine the Neovim archive directory name."

  rm -rf "/opt/${nvim_extract_dir}" /opt/nvim
  tar -C /opt -xzf "${nvim_tarball}"
  ln -sfn "/opt/${nvim_extract_dir}" /opt/nvim
  ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
  rm -f "${nvim_tarball}"
}

verify_versions() {
  local managed_python node_version npm_version codex_version

  managed_python="$(run_as_user 'uv python list --only-installed | head -n 1' || true)"
  node_version="$(run_as_user '
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh"
    node --version
  ')"
  npm_version="$(run_as_user '
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh"
    npm --version
  ')"
  codex_version="$(run_as_user '
    export NVM_DIR="$HOME/.nvm"
    . "$NVM_DIR/nvm.sh"
    if command -v codex >/dev/null 2>&1; then
      codex --version
    else
      npm list -g --depth=0 @openai/codex 2>/dev/null | tail -n 1
    fi
  ' || true)"

  log "Verification summary"
  printf '  uv: %s\n' "$(uv --version)"
  printf '  managed Python: %s\n' "${managed_python:-not found}"
  printf '  node: %s\n' "${node_version}"
  printf '  npm: %s\n' "${npm_version}"
  printf '  codex: %s\n' "${codex_version:-not found}"
  printf '  go: %s\n' "$(go version)"
  printf '  nvim: %s\n' "$(nvim --version | head -n 1)"
}

main() {
  require_root
  TARGET_USER="$(detect_target_user)"
  export TARGET_USER
  export DEBIAN_FRONTEND=noninteractive

  if ! is_wsl; then
    die "This script is intended for Ubuntu WSL only."
  fi

  if ! detect_ubuntu; then
    die "This script only supports Ubuntu Linux."
  fi

  log "Target user: ${TARGET_USER}"
  apt_install_packages
  install_uv_if_missing
  install_managed_python_for_user
  install_nvm_and_node_for_user
  install_codex_for_user
  install_latest_go
  install_latest_neovim
  verify_versions
  log "Provisioning complete"
}

main "$@"
