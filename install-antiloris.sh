#!/bin/sh

#
# mod_antiloris installation script
# Copyright (C) 2023 Filippo Lauria
# Copyright (C) 2023 Deltik
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

LATEST_VERSION="v0.7.1"
RELEASE_URL="https://github.com/Deltik/mod_antiloris/releases/download/${LATEST_VERSION}/mod_antiloris.so"

usage() {
  cat <<EOF
usage: $0 [-h] [--version VERSION] [-y] [--uninstall]

Installs mod_antiloris on an existing Apache HTTP Server

options:
  -h, --help                show this help message and exit
  --version VERSION         install named version (e.g. "${LATEST_VERSION}") rather than the default
  -y, --accept-disclaimer   bypass the disclaimer prompt
  --uninstall               uninstall mod_antiloris and remove its configuration
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --version)
      shift
      LATEST_VERSION="$1"
      RELEASE_URL="https://github.com/Deltik/mod_antiloris/releases/download/${LATEST_VERSION}/mod_antiloris.so"
      ;;
    -y | --accept-disclaimer)
      ACCEPT_DISCLAIMER="--accept-disclaimer"
      ;;
    --uninstall)
      UNINSTALL="yes"
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
    esac
    shift
  done
}

ensure_root() {
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      echo "[!] This script needs to be run as root. Elevating script to root with sudo."
      interpreter="$(head -1 "$0" | cut -c 3-)"
      if [ -x "$interpreter" ]; then
        sudo "$interpreter" "$0" "$@"
      else
        sudo "$0" "$@"
      fi
      exit $?
    else
      echo "[!] This script needs to be run as root."
      exit 1
    fi
  fi
}

detect_os() {
  OS=$(cat /etc/*-release | grep '^ID=' | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]')
  case $OS in
  debian | ubuntu)
    PATH_OF_MODULE="$(a2query -d)mod_antiloris.so"
    PATH_OF_MODAVAIL_DIR='/etc/apache2/mods-available'
    PATH_OF_MODENABL_DIR='/etc/apache2/mods-enabled'
    PATH_OF_LOADFILE="${PATH_OF_MODAVAIL_DIR}/antiloris.load"
    PATH_OF_CONFFILE="${PATH_OF_MODAVAIL_DIR}/antiloris.conf"
    PATH_OF_LOADLINK="${PATH_OF_MODENABL_DIR}/antiloris.load"
    PATH_OF_CONFLINK="${PATH_OF_MODENABL_DIR}/antiloris.conf"
    ;;
  *)
    echo "[!] This script does not support the ${OS} operating system."
    exit 1
    ;;
  esac
}

uninstall() {
  UNISTALL_LIST="${PATH_OF_LOADLINK}
${PATH_OF_CONFLINK}
${PATH_OF_MODULE}
${PATH_OF_LOADFILE}
${PATH_OF_CONFFILE}
"

  echo "[+] Uninstalling mod_antiloris..."

  OLD_IFS=$IFS
  IFS='
'
  for FULLNAME in $UNISTALL_LIST; do
    BASENAME=$(basename -- "${FULLNAME}")
    echo "[+] Removing ${BASENAME} symlink..."
    rm -f "${FULLNAME}"
  done
  IFS=$OLD_IFS

  echo "[+] Restarting Apache..."
  if systemctl restart apache2 2>/dev/null; then
    echo "[+] Apache restarted successfully."
  else
    echo "[!] Failed to restart Apache."
    exit 1
  fi

  echo "[+] mod_antiloris uninstalled successfully."
  exit 0
}

check_disclaimer() {
  if [ "$ACCEPT_DISCLAIMER" != "--accept-disclaimer" ]; then
    cat <<EOF
    [!] Hint: To avoid answering, you can pass the
              --accept-disclaimer option when launching the script.

EOF
    while [ "$ACCEPT_DISCLAIMER" != "yes" ]; do
      printf "[?] Are you okay with that? [yes/no]: "
      read -r ACCEPT_DISCLAIMER

      case $ACCEPT_DISCLAIMER in
      "yes") echo "[+] Very good!" ;;
      "no")
        echo "[!] Bye."
        exit
        ;;
      *)
        echo "[!] You have to answer yes or no."
        ACCEPT_DISCLAIMER=""
        ;;
      esac
    done
  else
    ACCEPT_DISCLAIMER="yes"
    echo "[+] Thanks for having accepted the disclaimer."
  fi
}

check_dependencies() {
  APACHE_EXISTS=$(command -v apache2 || command -v httpd)
  if [ -z "${APACHE_EXISTS}" ]; then
    echo "[!] Apache must be installed for this script to work."
    exit 1
  fi

  WGET_EXISTS=$(command -v wget)
  if [ -z "${WGET_EXISTS}" ]; then
    echo "[!] The wget utility must be installed for this script to work."
    exit 1
  fi
}

download_module() {
  TMP=$(mktemp -qu)
  echo "[+] Downloading the antiloris module..."
  wget -q "${RELEASE_URL}" -O "${TMP}"
  if [ ! -f "${TMP}" ]; then
    echo "[!] Failed to download the antiloris module."
    exit 1
  fi
}

install_module() {
  if [ -f "${PATH_OF_MODULE}" ]; then
    echo "[!] Overwriting another version of the antiloris module..."
    rm -f "${PATH_OF_MODULE}"
  fi

  echo "[+] Installing the antiloris module..."
  mv "${TMP}" "${PATH_OF_MODULE}"
  echo "LoadModule antiloris_module ${PATH_OF_MODULE}" >"${PATH_OF_LOADFILE}"
}

create_config() {
  cat <<EOF >"${PATH_OF_CONFFILE}"
<IfModule antiloris_module>
    # Maximum simultaneous connections in any state per IP address.
    # If set to 0, this limit does not apply.
    # IPTotalLimit    10

    # Maximum simultaneous idle connections per IP address.
    # If set to 0, this limit does not apply.
    IPOtherLimit      10

    # Maximum simultaneous connections in READ state per IP address.
    # If set to 0, this limit does not apply.
    IPReadLimit       10

    # Maximum simultaneous connections in WRITE state per IP address.
    # If set to 0, this limit does not apply.
    IPWriteLimit      10

    # Space-delimited list of IPv4 and IPv6 addresses, ranges, or CIDRs
    # which should not be subjected to any limits by this module.
    # This directive overrides is an alias for LocalIPs directive.
    # WhitelistIPs    127.0.0.1 ::1
</IfModule>

# vim: syntax=apache ts=4 sw=4 sts=4 sr noet
EOF
}

enable_module() {
  echo "[+] Enabling the antiloris module..."
  ln -sf "${PATH_OF_LOADFILE}" "${PATH_OF_LOADLINK}"
  ln -sf "${PATH_OF_CONFFILE}" "${PATH_OF_CONFLINK}"
}

check_config() {
  if ! apache2ctl configtest 2>/dev/null; then
    cat <<EOF
[!] Detected configuration file(s) with invalid syntax.
    Check your Apache configuration, then relaunch this script.
EOF
    exit 1
  fi
}

restart_apache() {
  echo "[+] Restarting Apache..."
  if systemctl restart apache2 2>/dev/null; then
    echo "[+] Apache restarted successfully."
  else
    echo "[!] Failed to restart Apache."
    exit 1
  fi
}

main() {
  parse_args "$@"
  ensure_root "$@"
  detect_os

  if [ "$UNINSTALL" = "yes" ]; then
    uninstall
  fi

  echo "[+] mod_antiloris installation script"
  cat <<EOF

[!] DISCLAIMER

    This script does not perform any backups, and the
    default actions for all files are to overwrite.

    Running this script does not guarantee the successful
    installation of the module, and its author is not
    responsible for any damages that may occur as a
    result of using this script.

EOF

  check_disclaimer
  check_dependencies
  download_module
  install_module
  create_config
  enable_module
  check_config
  restart_apache

  echo "[!] Antiloris module installation completed."
}

main "$@"
