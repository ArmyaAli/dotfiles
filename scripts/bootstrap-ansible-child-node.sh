#!/usr/bin/env bash
set -euo pipefail

ANSIBLE_USER="${ANSIBLE_USER:-ansible}"
ANSIBLE_GROUP="${ANSIBLE_GROUP:-${ANSIBLE_USER}}"
ANSIBLE_PUBLIC_KEY="${ANSIBLE_PUBLIC_KEY:-}"
ANSIBLE_PUBLIC_KEY_FILE="${ANSIBLE_PUBLIC_KEY_FILE:-}"
ANSIBLE_PASSWORDLESS_SUDO="${ANSIBLE_PASSWORDLESS_SUDO:-true}"
INSTALL_BASE_PACKAGES="${INSTALL_BASE_PACKAGES:-true}"

if [ "${EUID}" -ne 0 ]; then
  echo "Run as root (or with sudo)." >&2
  exit 1
fi

if [ -z "${ANSIBLE_PUBLIC_KEY}" ] && [ -n "${ANSIBLE_PUBLIC_KEY_FILE}" ]; then
  if [ ! -f "${ANSIBLE_PUBLIC_KEY_FILE}" ]; then
    echo "ANSIBLE_PUBLIC_KEY_FILE does not exist: ${ANSIBLE_PUBLIC_KEY_FILE}" >&2
    exit 1
  fi
  ANSIBLE_PUBLIC_KEY="$(cat "${ANSIBLE_PUBLIC_KEY_FILE}")"
fi

if [ -z "${ANSIBLE_PUBLIC_KEY}" ]; then
  echo "Provide ANSIBLE_PUBLIC_KEY or ANSIBLE_PUBLIC_KEY_FILE." >&2
  exit 1
fi

if [ "${INSTALL_BASE_PACKAGES}" = "true" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y sudo python3
  fi
fi

if ! getent group "${ANSIBLE_GROUP}" >/dev/null 2>&1; then
  groupadd "${ANSIBLE_GROUP}"
fi

if ! id -u "${ANSIBLE_USER}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash -g "${ANSIBLE_GROUP}" "${ANSIBLE_USER}"
fi

if [ -d /etc/sudoers.d ]; then
  if [ "${ANSIBLE_PASSWORDLESS_SUDO}" = "true" ]; then
    echo "${ANSIBLE_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${ANSIBLE_USER}"
  else
    echo "${ANSIBLE_USER} ALL=(ALL) ALL" > "/etc/sudoers.d/${ANSIBLE_USER}"
  fi
  chmod 0440 "/etc/sudoers.d/${ANSIBLE_USER}"
  if command -v visudo >/dev/null 2>&1; then
    visudo -cf "/etc/sudoers.d/${ANSIBLE_USER}" >/dev/null
  fi
fi

home_dir="$(getent passwd "${ANSIBLE_USER}" | cut -d: -f6)"
ssh_dir="${home_dir}/.ssh"
authorized_keys="${ssh_dir}/authorized_keys"

install -d -m 700 -o "${ANSIBLE_USER}" -g "${ANSIBLE_GROUP}" "${ssh_dir}"
touch "${authorized_keys}"

if ! grep -qxF "${ANSIBLE_PUBLIC_KEY}" "${authorized_keys}"; then
  echo "${ANSIBLE_PUBLIC_KEY}" >> "${authorized_keys}"
fi

chown -R "${ANSIBLE_USER}:${ANSIBLE_GROUP}" "${ssh_dir}"
chmod 700 "${ssh_dir}"
chmod 600 "${authorized_keys}"

echo "Ansible child-node bootstrap complete."
echo "User: ${ANSIBLE_USER}"
echo "Home: ${home_dir}"
