#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "Run as root (or with sudo)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

collect_public_keys() {
  local out_file="$1"
  : > "${out_file}"

  # Public keys available on this VM.
  local key_file
  for key_file in /root/.ssh/*.pub /home/*/.ssh/*.pub /vagrant/.ssh/*.pub; do
    if [ -f "${key_file}" ]; then
      cat "${key_file}" >> "${out_file}"
    fi
  done

  # Keys already trusted on this VM.
  local auth_file
  for auth_file in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
    if [ -f "${auth_file}" ]; then
      cat "${auth_file}" >> "${out_file}"
    fi
  done

  grep -E '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) ' "${out_file}" \
    | sort -u > "${out_file}.tmp" || true
  mv "${out_file}.tmp" "${out_file}"
}

sync_authorized_keys_for_user() {
  local user_name="$1"
  local key_source="$2"
  local passwd_entry
  local home_dir

  passwd_entry="$(getent passwd "${user_name}" || true)"
  if [ -z "${passwd_entry}" ]; then
    return
  fi
  home_dir="$(printf '%s\n' "${passwd_entry}" | cut -d: -f6)"

  install -d -m 700 -o "${user_name}" -g "${user_name}" "${home_dir}/.ssh"
  touch "${home_dir}/.ssh/authorized_keys"

  if [ -s "${key_source}" ]; then
    while IFS= read -r key_line; do
      if [ -n "${key_line}" ] && ! grep -qxF "${key_line}" "${home_dir}/.ssh/authorized_keys"; then
        echo "${key_line}" >> "${home_dir}/.ssh/authorized_keys"
      fi
    done < "${key_source}"
  fi

  chown -R "${user_name}:${user_name}" "${home_dir}/.ssh"
  chmod 700 "${home_dir}/.ssh"
  chmod 600 "${home_dir}/.ssh/authorized_keys"
}

install_nvm_and_node_for_user() {
  local user_name="$1"
  su - "${user_name}" -c "export PROFILE=\$HOME/.bashrc; export NVM_DIR=\$HOME/.nvm; if [ ! -s \"\$NVM_DIR/nvm.sh\" ]; then curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash; fi"
  su - "${user_name}" -c "export NVM_DIR=\$HOME/.nvm; . \"\$NVM_DIR/nvm.sh\"; nvm install node; nvm alias default node"
}

install_openai_codex_for_user() {
  local user_name="$1"
  su - "${user_name}" -c "export NVM_DIR=\$HOME/.nvm; . \"\$NVM_DIR/nvm.sh\"; npm install -g @openai/codex@latest"
}

install_available_packages() {
  local available_packages=()
  local pkg
  for pkg in "$@"; do
    if apt-cache show "${pkg}" >/dev/null 2>&1; then
      available_packages+=("${pkg}")
    else
      echo "Package unavailable on this distro, skipping: ${pkg}"
    fi
  done

  if [ "${#available_packages[@]}" -gt 0 ]; then
    apt-get install -y "${available_packages[@]}"
  fi
}

install_first_available_desktop_package() {
  local pkg
  for pkg in ubuntu-desktop-minimal kali-desktop-xfce xfce4; do
    if apt-cache show "${pkg}" >/dev/null 2>&1; then
      apt-get install -y "${pkg}"
      echo "Installed desktop package: ${pkg}"
      return 0
    fi
  done

  echo "No supported desktop package found; continuing without desktop metapackage."
}

install_latest_go() {
  local go_arch
  local go_url
  local go_tarball

  case "$(dpkg --print-architecture)" in
    amd64) go_arch="amd64" ;;
    arm64) go_arch="arm64" ;;
    *)
      echo "Unsupported architecture for Go install: $(dpkg --print-architecture)" >&2
      return 1
      ;;
  esac

  go_url="$(curl -fsSL "https://go.dev/dl/?mode=json" | jq -r --arg arch "${go_arch}" '.[] | select(.stable == true) | .files[] | select(.os == "linux" and .arch == $arch and .kind == "archive") | "https://go.dev/dl/" + .filename' | head -n1)"
  if [ -z "${go_url}" ] || [ "${go_url}" = "null" ]; then
    echo "Failed to resolve latest Go download URL." >&2
    return 1
  fi

  go_tarball="/tmp/go-latest.tar.gz"
  curl -fsSL "${go_url}" -o "${go_tarball}"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "${go_tarball}"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
}

install_latest_neovim() {
  local nvim_arch_pattern
  local nvim_asset_url
  local nvim_tarball
  local nvim_extract_dir

  case "$(dpkg --print-architecture)" in
    amd64) nvim_arch_pattern="(x86_64|64)" ;;
    arm64) nvim_arch_pattern="arm64" ;;
    *)
      echo "Unsupported architecture for Neovim install: $(dpkg --print-architecture)" >&2
      return 1
      ;;
  esac

  nvim_asset_url="$(curl -fsSL "https://api.github.com/repos/neovim/neovim/releases/latest" | jq -r --arg arch_pattern "${nvim_arch_pattern}" '.assets[]?.browser_download_url | select(test("nvim-linux-" + $arch_pattern + "\\.tar\\.gz$"))' | head -n1)"
  if [ -z "${nvim_asset_url}" ] || [ "${nvim_asset_url}" = "null" ]; then
    echo "Failed to resolve latest Neovim download URL." >&2
    return 1
  fi

  nvim_tarball="/tmp/nvim-latest.tar.gz"
  curl -fsSL "${nvim_asset_url}" -o "${nvim_tarball}"
  nvim_extract_dir="$(basename "${nvim_asset_url}" .tar.gz)"
  if [ -z "${nvim_extract_dir}" ]; then
    echo "Failed to detect Neovim archive directory." >&2
    return 1
  fi

  rm -rf "/opt/${nvim_extract_dir}" /opt/nvim
  tar -C /opt -xzf "${nvim_tarball}"
  ln -sfn "/opt/${nvim_extract_dir}" /opt/nvim
  ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
}

sync_neovim_config_for_user() {
  local user_name="$1"
  local source_dir="$2"
  local passwd_entry
  local home_dir
  local target_dir

  if [ ! -d "${source_dir}" ]; then
    echo "Neovim source directory not found: ${source_dir}" >&2
    return 1
  fi

  passwd_entry="$(getent passwd "${user_name}" || true)"
  if [ -z "${passwd_entry}" ]; then
    echo "User not found for Neovim sync: ${user_name}" >&2
    return 1
  fi
  home_dir="$(printf '%s\n' "${passwd_entry}" | cut -d: -f6)"
  target_dir="${home_dir}/.config/nvim"

  install -d -m 755 -o "${user_name}" -g "${user_name}" "${home_dir}/.config"
  rm -rf "${target_dir}"
  install -d -m 755 -o "${user_name}" -g "${user_name}" "${target_dir}"
  cp -a "${source_dir}/." "${target_dir}/"
  chown -R "${user_name}:${user_name}" "${target_dir}"
}

# Base system update/upgrade (non-interactive).
apt-get update
apt-get -y upgrade

# Install requested tools and Docker engine from distro repos.
install_available_packages \
  ansible \
  build-essential \
  ca-certificates \
  jq \
  make \
  net-tools \
  ripgrep \
  docker.io \
  telnet \
  unzip \
  wget \
  gcc \
  g++ \
  python3 \
  python3-pip \
  curl

# Install a desktop package based on distro availability.
install_first_available_desktop_package

# Install uv (Python package/project manager) system-wide.
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh
fi

# Enable and start Docker daemon.
systemctl enable docker
systemctl start docker

# Ensure docker group exists.
if ! getent group docker >/dev/null; then
  groupadd docker
fi

# Create a dedicated docker user and grant non-root Docker access via group membership.
if ! id -u docker >/dev/null 2>&1; then
  useradd -m -s /bin/bash -g docker -N docker
fi
usermod -aG docker docker

# Also allow vagrant user to run docker without sudo.
if id -u vagrant >/dev/null 2>&1; then
  usermod -aG docker vagrant
fi

# Create a dev user with requested credentials.
if ! id -u dev >/dev/null 2>&1; then
  useradd -m -s /bin/bash dev
fi
echo "dev:dev" | chpasswd
if getent group sudo >/dev/null 2>&1; then
  usermod -aG sudo dev
fi

# Install latest managed Python with uv for vagrant/dev.
if id -u vagrant >/dev/null 2>&1; then
  su - vagrant -c "uv python install"
fi
su - dev -c "uv python install"

# Install latest Node.js with nvm for vagrant/dev.
if id -u vagrant >/dev/null 2>&1; then
  install_nvm_and_node_for_user vagrant
fi
install_nvm_and_node_for_user dev

# Install OpenAI Codex CLI globally for vagrant/dev after Node setup.
if id -u vagrant >/dev/null 2>&1; then
  install_openai_codex_for_user vagrant
fi
install_openai_codex_for_user dev

# Install latest Go from official distribution archives.
install_latest_go

# Install latest stable Neovim from official releases.
install_latest_neovim

# Install repo Neovim config for dev user.
sync_neovim_config_for_user dev /dotfiles-neovim

# Gather all available public keys and trust them for vagrant/dev.
TMP_PUBLIC_KEYS="$(mktemp)"
collect_public_keys "${TMP_PUBLIC_KEYS}"

if id -u vagrant >/dev/null 2>&1; then
  sync_authorized_keys_for_user vagrant "${TMP_PUBLIC_KEYS}"
fi
sync_authorized_keys_for_user dev "${TMP_PUBLIC_KEYS}"
rm -f "${TMP_PUBLIC_KEYS}"

# Add vi mode to shell startup.
for rc in /home/vagrant/.bashrc /home/docker/.bashrc /home/dev/.bashrc; do
  if [ -f "${rc}" ] && ! grep -Fq "set -o vi" "${rc}"; then
    echo "set -o vi" >> "${rc}"
  fi
done

if [ ! -f /etc/profile.d/vi-mode.sh ]; then
  cat > /etc/profile.d/vi-mode.sh <<'PROFILEEOF'
if [ -n "${BASH_VERSION:-}" ]; then
  set -o vi
fi
PROFILEEOF
  chmod 644 /etc/profile.d/vi-mode.sh
fi

echo "Provisioning complete."
