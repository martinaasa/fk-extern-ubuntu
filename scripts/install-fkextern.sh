#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="/tmp/fkextern-install.log"

FKEXTERN_VERSION="2605"
FKEXTERN_PACKAGE_BASENAME="FKextern2605_ubuntu_PoC"
FKEXTERN_BASE_URL="https://download.forsakringskassan.se/FK/Linux"

PACKAGE_URL="${PACKAGE_URL:-$FKEXTERN_BASE_URL/$FKEXTERN_PACKAGE_BASENAME}"
PACKAGE_ZIP_NAME="${PACKAGE_ZIP_NAME:-$FKEXTERN_PACKAGE_BASENAME.zip}"

DOWNLOAD_DIR="${DOWNLOAD_DIR:-/tmp/fkextern${FKEXTERN_VERSION}_download}"
EXTRACT_DIR="${EXTRACT_DIR:-/tmp/fkextern${FKEXTERN_VERSION}_extracted}"
MEDIA_DIR="${MEDIA_DIR:-}"

CITRIX_CLIENT_DEB="${CITRIX_CLIENT_DEB:-icaclient_26.01.0.150_amd64.deb}"
CITRIX_USB_DEB="${CITRIX_USB_DEB:-ctxusb_26.01.0.150_amd64.deb}"
NETID_ARCHIVE="${NETID_ARCHIVE:-netidsetup_v1.3.4.10_linux_fk-001.tar.gz}"

NETID_LIB="${NETID_LIB:-/lib/netid/libnetid.so}"
NETID_MODULE_NAME="${NETID_MODULE_NAME:-Net iD}"

RESET_BEFORE_INSTALL=1
PURGE_PCSCD=0
REGISTER_NETID_IN_FIREFOX=1
CHECK_CARD_READER=1
FORCE_DOWNLOAD=0
ASSUME_YES=0
DRY_RUN=0
FORCE_UNSUPPORTED_OS=0

RESET_USER_CITRIX_CACHE=0
SET_CITRIX_PCSCLIBRARY_FULL_PATH=0
DISABLE_CITRIX_USB_SMARTCARD=0

APT_UPDATED=0

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

ok() {
  log "[OK] $*"
}

warn() {
  log "[WARN] $*"
}

fail() {
  echo
  log "[FEL] $*"
  exit 1
}

usage() {
  cat <<EOF
Användning:
  $SCRIPT_NAME [flaggor]

Installerar FK Extern-komponenter på Ubuntu.

Krav:
  Firefox måste redan vara installerat som riktig .deb.
  Snap- och Flatpak-Firefox stöds inte.

Firefox .deb-migrering:
  https://github.com/martinaasa/ubuntu-firefox-deb-migration

Vanliga flaggor:
  --help                              Visa hjälp
  --yes                               Kör utan bekräftelseprompt
  --dry-run                           Visa planerade steg utan att installera
  --no-reset                          Rensa inte tidigare Citrix/NetiD-installation
  --reset                             Rensa tidigare Citrix/NetiD-installation, default
  --purge-pcscd                       Ta även bort/installera om pcscd och pcsc-tools
  --skip-card-reader-check            Hoppa över pcsc_scan/kortläsarkontroll
  --no-firefox-register               Registrera inte Net iD i Firefox-profiler
  --force-download                    Hämta och packa upp FK-paketet på nytt
  --force-unsupported-os              Tillåt körning på ej verifierad Ubuntu-version
  --media-dir PATH                    Använd lokalt uppackat media
  --package-url URL                   Hämta FK-paket från annan URL

Felsökningsflaggor, inte default:
  --reset-user-citrix-cache           Flytta undan $HOME/.ICAClient
  --set-citrix-pcsclibrary-full-path  Sätt PCSCLibraryName till full sökväg
  --disable-citrix-usb-smartcard      Lägg DENY för smartcard class=0b i Citrix USB-config

Exempel:
  ./$SCRIPT_NAME
  ./$SCRIPT_NAME --yes
  ./$SCRIPT_NAME --no-reset
  ./$SCRIPT_NAME --media-dir ./ubuntu_extern2605
  ./$SCRIPT_NAME --force-download --yes
EOF
}

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] $*"
  else
    "$@"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help | -h)
        usage
        exit 0
        ;;
      --yes | -y)
        ASSUME_YES=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --no-reset)
        RESET_BEFORE_INSTALL=0
        shift
        ;;
      --reset)
        RESET_BEFORE_INSTALL=1
        shift
        ;;
      --purge-pcscd)
        PURGE_PCSCD=1
        shift
        ;;
      --skip-card-reader-check)
        CHECK_CARD_READER=0
        shift
        ;;
      --no-firefox-register)
        REGISTER_NETID_IN_FIREFOX=0
        shift
        ;;
      --force-download)
        FORCE_DOWNLOAD=1
        shift
        ;;
      --force-unsupported-os)
        FORCE_UNSUPPORTED_OS=1
        shift
        ;;
      --reset-user-citrix-cache)
        RESET_USER_CITRIX_CACHE=1
        shift
        ;;
      --set-citrix-pcsclibrary-full-path)
        SET_CITRIX_PCSCLIBRARY_FULL_PATH=1
        shift
        ;;
      --disable-citrix-usb-smartcard)
        DISABLE_CITRIX_USB_SMARTCARD=1
        shift
        ;;
      --media-dir)
        if [[ $# -lt 2 ]]; then
          fail "--media-dir kräver sökväg"
        fi

        MEDIA_DIR="$2"
        shift 2
        ;;
      --package-url)
        if [[ $# -lt 2 ]]; then
          fail "--package-url kräver URL"
        fi

        PACKAGE_URL="$2"
        shift 2
        ;;
      *)
        fail "Okänd flagga: $1"
        ;;
    esac
  done
}

require_cmd() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail "Saknar kommando: $command_name"
  fi
}

apt_update_once() {
  if [[ "$APT_UPDATED" == "0" ]]; then
    log "Kör apt-get update..."
    run sudo apt-get update
    APT_UPDATED=1
  fi
}

apt_install_package() {
  local package="$1"

  if dpkg -s "$package" >/dev/null 2>&1; then
    ok "$package är redan installerat."
    return
  fi

  apt_update_once
  log "Installerar $package..."
  run sudo apt-get install -y "$package"
}

apt_purge_if_installed() {
  local package="$1"

  if dpkg -s "$package" >/dev/null 2>&1; then
    log "Tar bort paket: $package"
    run sudo apt-get purge -y "$package" || true
  else
    log "$package är inte installerat."
  fi
}

remove_path_if_exists() {
  local path="$1"

  if [[ -e "$path" || -L "$path" ]]; then
    log "Tar bort: $path"
    run sudo rm -rf "$path"
  else
    log "Finns inte, hoppar över: $path"
  fi
}

check_ubuntu() {
  log "=== Kontrollerar OS ==="

  if [[ ! -f /etc/os-release ]]; then
    fail "Kan inte läsa /etc/os-release. Endast Ubuntu stöds."
  fi

  # shellcheck source=/dev/null
  . /etc/os-release

  log "OS: ${PRETTY_NAME:-okänt}"

  if [[ "${ID:-}" != "ubuntu" ]]; then
    fail "Detta script är endast avsett för Ubuntu. Identifierat: ${PRETTY_NAME:-okänt}"
  fi

  case "${VERSION_ID:-}" in
    24.04 | 26.04)
      ok "Ubuntu ${VERSION_ID} är inom avsett testscope."
      ;;
    *)
      if [[ "$FORCE_UNSUPPORTED_OS" == "1" ]]; then
        warn "Ubuntu ${VERSION_ID:-okänd} är inte uttryckligen testad. Fortsätter p.g.a. --force-unsupported-os."
      else
        fail "Ubuntu ${VERSION_ID:-okänd} är inte uttryckligen testad. Använd --force-unsupported-os för att fortsätta."
      fi
      ;;
  esac
}

check_firefox_deb() {
  log "=== Kontrollerar att Firefox .deb är installerad ==="

  if ! command -v firefox >/dev/null 2>&1; then
    fail "Firefox saknas. Installera Firefox .deb först: https://github.com/martinaasa/ubuntu-firefox-deb-migration"
  fi

  local firefox_command
  local firefox_realpath
  local firefox_version

  firefox_command="$(command -v firefox)"
  firefox_realpath="$(readlink -f "$firefox_command" 2>/dev/null || echo "$firefox_command")"
  firefox_version="$(firefox --version 2>/dev/null || true)"

  log "firefox command: $firefox_command"
  log "firefox realpath: $firefox_realpath"
  log "firefox version: ${firefox_version:-okänd}"

  if [[ "$firefox_realpath" == /snap/* ]]; then
    fail "Firefox pekar på Snap. Installera .deb-version först."
  fi

  if [[ "$firefox_realpath" == /app/* ]]; then
    fail "Firefox pekar på Flatpak. Installera .deb-version först."
  fi

  if [[ -f /usr/bin/firefox ]] && grep -q /snap/bin/firefox /usr/bin/firefox 2>/dev/null; then
    fail "/usr/bin/firefox är en Snap-wrapper. Installera .deb-version först."
  fi

  if ! dpkg -s firefox >/dev/null 2>&1; then
    fail "dpkg-paketet firefox är inte installerat. Installera .deb-version först."
  fi

  if ! dpkg -S "$firefox_realpath" >/dev/null 2>&1; then
    fail "Firefox-binären verkar inte ägas av ett deb-paket: $firefox_realpath"
  fi

  ok "Firefox .deb-kontroll OK."
}

has_required_media_files() {
  local directory="$1"

  [[ -f "$directory/$CITRIX_CLIENT_DEB" ]] \
    && [[ -f "$directory/$CITRIX_USB_DEB" ]] \
    && [[ -f "$directory/$NETID_ARCHIVE" ]]
}

find_media_dir_under() {
  local root="$1"
  local candidate

  if [[ ! -d "$root" ]]; then
    return 1
  fi

  while IFS= read -r candidate; do
    if has_required_media_files "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done < <(find "$root" -type f -name "$CITRIX_CLIENT_DEB" -printf '%h\n' 2>/dev/null)

  return 1
}

download_file() {
  local url="$1"
  local output="$2"
  local status_file
  local http_code

  status_file="$(mktemp)"
  rm -f "$output"

  if command -v curl >/dev/null 2>&1; then
    http_code="$(
      curl \
        --fail \
        --location \
        --progress-bar \
        --output "$output" \
        --write-out "%{http_code}" \
        "$url" 2>"$status_file" || true
    )"

    if [[ "$http_code" == "200" ]]; then
      rm -f "$status_file"
      return 0
    fi

    rm -f "$output"

    if [[ "$http_code" == "404" ]]; then
      rm -f "$status_file"
      return 44
    fi

    log "Nedladdning misslyckades från $url"
    log "HTTP-status: ${http_code:-okänd}"

    if [[ -s "$status_file" ]]; then
      log "curl-fel: $(cat "$status_file")"
    fi

    rm -f "$status_file"
    return 1
  fi

  if command -v wget >/dev/null 2>&1; then
    if wget --progress=bar:force -O "$output" "$url" 2>"$status_file"; then
      rm -f "$status_file"
      return 0
    fi

    rm -f "$output"

    if grep -q 404 "$status_file"; then
      rm -f "$status_file"
      return 44
    fi

    log "Nedladdning misslyckades från $url"

    if [[ -s "$status_file" ]]; then
      log "wget-fel: $(cat "$status_file")"
    fi

    rm -f "$status_file"
    return 1
  fi

  fail "Saknar både curl och wget."
}

download_and_extract_media() {
  log "=== Hämtar FK Extern-paket ==="

  apt_install_package unzip

  if [[ "$FORCE_DOWNLOAD" == "1" ]]; then
    log "FORCE_DOWNLOAD=1, rensar tidigare hämtning och uppackning."
    rm -rf "$DOWNLOAD_DIR" "$EXTRACT_DIR"
  fi

  mkdir -p "$DOWNLOAD_DIR" "$EXTRACT_DIR"

  local zip_path
  local urls_to_try
  local downloaded
  local saw_404
  local url
  local rc

  zip_path="$DOWNLOAD_DIR/$PACKAGE_ZIP_NAME"
  urls_to_try=("$PACKAGE_URL")

  if [[ "$PACKAGE_URL" != *.zip ]]; then
    urls_to_try+=("${PACKAGE_URL}.zip")
  fi

  if [[ -f "$zip_path" && "$FORCE_DOWNLOAD" != "1" ]]; then
    log "Zip finns redan lokalt: $zip_path"
  else
    downloaded=0
    saw_404=0

    for url in "${urls_to_try[@]}"; do
      log "Försöker hämta: $url"
      log "Paketet är stort. Nedladdningen kan ta en stund."

      set +e
      download_file "$url" "$zip_path"
      rc=$?
      set -e

      if [[ "$rc" -eq 0 ]]; then
        downloaded=1
        ok "Hämtning lyckades: $url"
        break
      fi

      if [[ "$rc" -eq 44 ]]; then
        saw_404=1
        warn "Paketet hittades inte på: $url"
        continue
      fi

      warn "Kunde inte hämta från: $url"
    done

    if [[ "$downloaded" != "1" ]]; then
      if [[ "$saw_404" == "1" ]]; then
        fail "FK Extern-paketet hittades inte. Sannolikt har en nyare version ersatt paketet under $FKEXTERN_BASE_URL. Scriptet behöver uppdateras."
      fi

      fail "Kunde inte hämta FK Extern-paketet."
    fi
  fi

  if [[ ! -s "$zip_path" ]]; then
    fail "Zip-filen saknas eller är tom: $zip_path"
  fi

  if ! unzip -t "$zip_path" >/dev/null 2>&1; then
    fail "Nedladdad fil är inte en giltig zip: $zip_path"
  fi

  rm -rf "$EXTRACT_DIR"
  mkdir -p "$EXTRACT_DIR"
  unzip -q -o "$zip_path" -d "$EXTRACT_DIR"

  if MEDIA_DIR="$(find_media_dir_under "$EXTRACT_DIR")"; then
    ok "Hittade media-katalog: $MEDIA_DIR"
  else
    fail "Zippen saknar förväntade filer: $CITRIX_CLIENT_DEB, $CITRIX_USB_DEB, $NETID_ARCHIVE. Scriptet behöver uppdateras."
  fi
}

ensure_media_dir() {
  log "=== Letar efter FK Extern-media ==="

  local script_dir

  if [[ -n "$MEDIA_DIR" ]]; then
    if has_required_media_files "$MEDIA_DIR"; then
      ok "Använder MEDIA_DIR: $MEDIA_DIR"
      return
    fi

    warn "MEDIA_DIR saknar nödvändiga filer: $MEDIA_DIR"
  fi

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if has_required_media_files "$script_dir"; then
    MEDIA_DIR="$script_dir"
    ok "Använder scriptets katalog: $MEDIA_DIR"
    return
  fi

  if MEDIA_DIR="$(find_media_dir_under "$script_dir")"; then
    ok "Hittade media under scriptets katalog: $MEDIA_DIR"
    return
  fi

  if [[ "$FORCE_DOWNLOAD" != "1" ]]; then
    if MEDIA_DIR="$(find_media_dir_under "$EXTRACT_DIR")"; then
      ok "Hittade media i tidigare uppackning: $MEDIA_DIR"
      return
    fi
  fi

  download_and_extract_media
}

copy_deb_to_tmp() {
  local source_path="$1"
  local target_directory="/tmp/ubuntu_extern2605_media"
  local source_basename
  local target_path

  source_basename="$(basename "$source_path")"
  target_path="$target_directory/$source_basename"

  run sudo mkdir -p "$target_directory"
  run sudo cp -f "$source_path" "$target_path"
  run sudo chmod 0644 "$target_path"

  echo "$target_path"
}

install_deb_package() {
  local deb_path="$1"
  local package_hint="$2"
  local package_name
  local tmp_deb_path

  if [[ ! -f "$deb_path" ]]; then
    fail "Saknar deb-paket: $deb_path"
  fi

  package_name="$(dpkg-deb -f "$deb_path" Package 2>/dev/null || echo "$package_hint")"

  if dpkg -s "$package_name" >/dev/null 2>&1; then
    ok "$package_name är redan installerat."
    return
  fi

  tmp_deb_path="$(copy_deb_to_tmp "$deb_path")"

  log "Installerar deb-paket: $tmp_deb_path"
  log "Om Citrix frågar om AppProtection/DeviceTrust/EPAClient: välj no."

  run sudo apt-get install -y "$tmp_deb_path"
}

stop_user_processes() {
  pkill firefox 2>/dev/null || true
  pkill firefox-bin 2>/dev/null || true
  pkill wfica 2>/dev/null || true
  pkill -f '/opt/Citrix/ICAClient/adapter' 2>/dev/null || true
  pkill -f ctxwebhelper 2>/dev/null || true
  pkill -f icasessionmgr 2>/dev/null || true
  pkill -f AuthManagerDaemon 2>/dev/null || true
  pkill -f ServiceRecord 2>/dev/null || true
  pkill -f selfservice 2>/dev/null || true
}

reset_installation() {
  log "=== Rensar tidigare FK Extern-installation ==="

  stop_user_processes
  sleep 1

  apt_purge_if_installed ctxusb
  apt_purge_if_installed icaclient

  if [[ "$PURGE_PCSCD" == "1" ]]; then
    run sudo systemctl stop pcscd 2>/dev/null || true
    apt_purge_if_installed pcsc-tools
    apt_purge_if_installed pcscd
  fi

  remove_path_if_exists /lib/netid
  remove_path_if_exists /usr/lib/netid
  remove_path_if_exists /usr/share/netid
  remove_path_if_exists /usr/local/lib/netid
  remove_path_if_exists /etc/netid
  remove_path_if_exists /opt/netid
  remove_path_if_exists /usr/bin/netid
  remove_path_if_exists /usr/local/bin/netid
  remove_path_if_exists /etc/systemd/system/netid.service
  remove_path_if_exists /etc/systemd/system/netid-monitor.service
  remove_path_if_exists /etc/systemd/system/netid-service.service
  remove_path_if_exists /usr/lib/systemd/system/netid.service
  remove_path_if_exists /usr/lib/systemd/system/netid-monitor.service
  remove_path_if_exists /usr/lib/systemd/system/netid-service.service
  remove_path_if_exists /etc/xdg/autostart/netid.desktop
  remove_path_if_exists /usr/share/applications/netid.desktop
  remove_path_if_exists /tmp/ubuntu_extern2605_media

  run sudo systemctl daemon-reload || true

  ok "Rensning klar."
}

reset_user_citrix_cache_if_requested() {
  local backup_path

  if [[ "$RESET_USER_CITRIX_CACHE" != "1" ]]; then
    log "Behåller användarens Citrix-cache $HOME/.ICAClient."
    return
  fi

  if [[ -d "$HOME/.ICAClient" ]]; then
    backup_path="$HOME/.ICAClient.bak.$(date +%Y%m%d-%H%M%S)"
    log "Flyttar $HOME/.ICAClient till $backup_path"
    run mv "$HOME/.ICAClient" "$backup_path"
  else
    log "$HOME/.ICAClient finns inte."
  fi
}

install_pcsc_and_reader_tools() {
  log "=== Installerar pcscd och kortläsarverktyg ==="

  apt_install_package pcscd
  apt_install_package pcsc-tools
  apt_install_package libccid
  apt_install_package libnss3-tools
  apt_install_package libpcsclite-dev

  run sudo systemctl enable pcscd
  run sudo systemctl restart pcscd

  if systemctl is-active --quiet pcscd; then
    ok "pcscd är aktiv."
  else
    fail "pcscd är inte aktiv."
  fi
}

verify_pcsclite_for_citrix() {
  log "=== Verifierar libpcsclite för Citrix ==="

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] skulle verifiera libpcsclite.so"
    return
  fi

  sudo ldconfig || true

  local candidates
  local path
  local found

  candidates=(
    "/usr/lib/x86_64-linux-gnu/libpcsclite.so"
    "/usr/lib64/libpcsclite.so"
    "/usr/lib/libpcsclite.so"
  )

  found=""

  for path in "${candidates[@]}"; do
    if [[ -e "$path" ]]; then
      found="$path"
      break
    fi
  done

  if [[ -z "$found" ]] && command -v ldconfig >/dev/null 2>&1; then
    found="$(ldconfig -p 2>/dev/null | awk '/libpcsclite\.so[[:space:]]*\(/ {print $NF; exit}')"
  fi

  if [[ -n "$found" && -e "$found" ]]; then
    ok "libpcsclite.so finns: $found"
    ldconfig -p 2>/dev/null | grep 'libpcsclite\.so' | tee -a "$LOG_FILE" || true
    return
  fi

  log "dpkg-status för libpcsclite-dev:"
  dpkg -s libpcsclite-dev 2>/dev/null | sed -n '1,20p' | tee -a "$LOG_FILE" || true

  log "Filer från libpcsclite-dev:"
  dpkg -L libpcsclite-dev 2>/dev/null | grep 'libpcsclite\.so' | tee -a "$LOG_FILE" || true

  fail "Citrix behöver kunna ladda libpcsclite.so, men scriptet hittar den inte.

Försök:
  sudo apt install --reinstall libpcsclite-dev
  sudo ldconfig

Kontrollera sedan:
  dpkg -L libpcsclite-dev | grep libpcsclite.so
  ldconfig -p | grep pcsclite"
}

install_citrix() {
  log "=== Installerar Citrix Workspace App och USB-stöd ==="

  install_deb_package "$MEDIA_DIR/$CITRIX_CLIENT_DEB" icaclient
  install_deb_package "$MEDIA_DIR/$CITRIX_USB_DEB" ctxusb

  ok "Citrix-installation klar."
}

install_netid() {
  log "=== Installerar NetiD Client ==="

  local tmp_directory
  local installer_directory

  tmp_directory="$(mktemp -d)"

  tar -xzf "$MEDIA_DIR/$NETID_ARCHIVE" -C "$tmp_directory"

  installer_directory="$(find "$tmp_directory" -maxdepth 3 -type f -name install -printf '%h\n' | head -n 1)"

  if [[ -z "$installer_directory" ]]; then
    rm -rf "$tmp_directory"
    fail "Hittade ingen NetiD-installerare"
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] skulle köra NetiD-installeraren"
  else
    (
      cd "$installer_directory"
      printf 'y\n' | sudo ./install
    )
  fi

  rm -rf "$tmp_directory"

  if [[ "$DRY_RUN" != "1" && ! -f "$NETID_LIB" ]]; then
    fail "NetiD installerades men $NETID_LIB saknas"
  fi

  ok "NetiD installerat."
}

configure_citrix_optional() {
  local module_ini="/opt/Citrix/ICAClient/config/module.ini"
  local usb_conf="/opt/Citrix/ICAClient/usb.conf"
  local backup_suffix
  local pcsclite_path
  local tmp_file

  if [[ "$SET_CITRIX_PCSCLIBRARY_FULL_PATH" != "1" &&
    "$DISABLE_CITRIX_USB_SMARTCARD" != "1" ]]; then
    log "Hoppar över ändring av Citrix-konfig. Standardkonfiguration lämnas orörd."
    return
  fi

  log "=== Felsökningsläge: ändrar begränsad Citrix-konfig ==="

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] skulle ändra begränsad Citrix-konfig"
    return
  fi

  backup_suffix="$(date +%Y%m%d-%H%M%S)"

  if [[ -f "$module_ini" ]]; then
    sudo cp -a "$module_ini" "$module_ini.bak.$backup_suffix"
    log "Backup: $module_ini.bak.$backup_suffix"
  else
    warn "Saknar $module_ini"
  fi

  if [[ -f "$usb_conf" ]]; then
    sudo cp -a "$usb_conf" "$usb_conf.bak.$backup_suffix"
    log "Backup: $usb_conf.bak.$backup_suffix"
  else
    warn "Saknar $usb_conf"
  fi

  if [[ "$SET_CITRIX_PCSCLIBRARY_FULL_PATH" == "1" ]]; then
    if [[ -f "$module_ini" ]]; then
      pcsclite_path="$(ldconfig -p 2>/dev/null | awk '/libpcsclite\.so /{print $NF; exit}')"

      if [[ -z "$pcsclite_path" && -e /usr/lib/x86_64-linux-gnu/libpcsclite.so ]]; then
        pcsclite_path="/usr/lib/x86_64-linux-gnu/libpcsclite.so"
      fi

      if [[ -n "$pcsclite_path" ]]; then
        sudo sed -i "s#^PCSCLibraryName *=.*#PCSCLibraryName = $pcsclite_path#" "$module_ini"
        log "Satte PCSCLibraryName = $pcsclite_path"
      else
        warn "Kunde inte hitta libpcsclite.so."
      fi
    fi
  fi

  if [[ "$DISABLE_CITRIX_USB_SMARTCARD" == "1" ]]; then
    if [[ -f "$usb_conf" ]]; then
      if grep -Eq '^DENY:[[:space:]]+class=0b' "$usb_conf"; then
        log "Citrix USB-config har redan DENY för smartcard class=0b."
      else
        tmp_file="$(mktemp)"

        {
          echo 'DENY:  class=0b # Smartcard readers should use smart card remoting, not generic USB'
          cat "$usb_conf"
        } >"$tmp_file"

        sudo cp "$tmp_file" "$usb_conf"
        rm -f "$tmp_file"

        log "Lade till DENY för smartcard class=0b i Citrix USB-config."
      fi
    fi
  fi

  ok "Begränsad Citrix-konfigändring klar."
}

register_netid_in_profile() {
  local profile_directory="$1"

  if [[ ! -d "$profile_directory" ]]; then
    return
  fi

  log "Registrerar NetI D i Firefox-profil: $profile_directory"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] skulle registrera NetiD i Firefox-profil"
    return
  fi

  if [[ ! -f "$profile_directory/cert9.db" ]]; then
    modutil -force -dbdir "sql:$profile_directory" -create || true
  fi

  if modutil -dbdir "sql:$profile_directory" -list 2>/dev/null | grep -q "$NETID_MODULE_NAME"; then
    modutil -force -dbdir "sql:$profile_directory" -delete "$NETID_MODULE_NAME" || true
  fi

  modutil -force \
    -dbdir "sql:$profile_directory" \
    -add "$NETID_MODULE_NAME" \
    -libfile "$NETID_LIB" \
    -mechanisms FRIENDLY || true

  if modutil -dbdir "sql:$profile_directory" -list 2>/dev/null | grep -q "$NETID_MODULE_NAME"; then
    ok "Net iD registrerad i $profile_directory"
  else
    warn "Net iD kunde inte verifieras i $profile_directory"
  fi
}

register_netid_in_firefox_profiles() {
  local firefox_root
  local profile_list_file
  local profile_path

  log "=== Registrerar NetiD i deb-Firefox-profiler ==="

  if [[ "$REGISTER_NETID_IN_FIREFOX" != "1" ]]; then
    log "Hoppar över Firefox-registrering."
    return
  fi

  if [[ "$DRY_RUN" != "1" ]]; then
    require_cmd modutil
  fi

  pkill firefox 2>/dev/null || true
  pkill firefox-bin 2>/dev/null || true

  firefox_root="$HOME/.mozilla/firefox"
  mkdir -p "$firefox_root"

  profile_list_file="$(mktemp)"

  if [[ -f "$firefox_root/profiles.ini" ]]; then
    while IFS= read -r profile_path; do
      if [[ "$profile_path" = /* ]]; then
        echo "$profile_path" >>"$profile_list_file"
      else
        echo "$firefox_root/$profile_path" >>"$profile_list_file"
      fi
    done < <(awk -F= '/^Path=/{print $2}' "$firefox_root/profiles.ini")
  fi

  find "$firefox_root" -maxdepth 2 -type f -name cert9.db -printf '%h\n' 2>/dev/null >>"$profile_list_file"

  if [[ ! -s "$profile_list_file" ]]; then
    warn "Hittade ingen Firefox-profil under $firefox_root."
    rm -f "$profile_list_file"
    return
  fi

  sort -u "$profile_list_file" | while IFS= read -r profile_path; do
    register_netid_in_profile "$profile_path"
  done

  rm -f "$profile_list_file"
}

check_card_reader() {
  log "=== Läser in/kontrollerar kortläsare ==="

  if [[ "$CHECK_CARD_READER" != "1" ]]; then
    log "Hoppar över kortläsarkontroll."
    return
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] skulle köra kortläsarkontroll"
    return
  fi

  sudo systemctl restart pcscd
  sleep 2

  if command -v pcsc_scan >/dev/null 2>&1; then
    log "Kör pcsc_scan i max 8 sekunder. Timeout är förväntat."
    timeout 8 pcsc_scan 2>&1 | tee -a "$LOG_FILE" || true
    echo | tee -a "$LOG_FILE"
    log "pcsc_scan avslutad efter timeout. Detta är förväntat."
  else
    warn "pcsc_scan saknas."
  fi
}

print_preflight() {
  cat <<EOF

============================================================
Preflight
============================================================
Detta script installerar FK Extern-komponenter för Ubuntu.

Endast för anställda/konsulter på Försäkringskassan.
Ingen support ges på scriptet.
Scriptet är vibe-kodat. Läs igenom det innan användning.

Firefox måste redan vara .deb.

Media: ${MEDIA_DIR:-automatisk}
Logg: $LOG_FILE
============================================================

EOF
}

confirm_continue() {
  local answer

  if [[ "$ASSUME_YES" == "1" || "$DRY_RUN" == "1" ]]; then
    return
  fi

  read -r -p "Fortsätta? [y/N] " answer

  case "$answer" in
    y | Y | yes | YES | ja | Ja)
      return
      ;;
    *)
      fail "Avbrutet av användaren."
      ;;
  esac
}

print_summary() {
  cat <<EOF

============================================================
FK Extern-installation klar
============================================================

Net iD:
  $NETID_LIB

Citrix:
  Standardkonfiguration har lämnats orörd om du inte använde explicit felsökningsflagga.

Viktigt:
  Starta om datorn efter installationen innan du testar Citrix/remote desktop.

  Utan omstart kan smartkortet rapporteras som tomt eller PIN-flödet utebli.

Logg:
  $LOG_FILE

============================================================

EOF

  if [[ "$DRY_RUN" != "1" ]]; then
    touch /tmp/fkextern-reboot-required 2>/dev/null || true
  fi
}

main() {
  parse_args "$@"

  log "Startar $SCRIPT_NAME"

  require_cmd sudo
  require_cmd dpkg
  require_cmd apt-get
  require_cmd grep
  require_cmd readlink
  require_cmd awk
  require_cmd find

  sudo -v

  print_preflight
  confirm_continue

  check_ubuntu
  check_firefox_deb
  ensure_media_dir

  log "Använder media-katalog: $MEDIA_DIR"

  if [[ "$RESET_BEFORE_INSTALL" == "1" ]]; then
    reset_installation
  else
    log "Hoppar över rensning."
  fi

  reset_user_citrix_cache_if_requested
  install_pcsc_and_reader_tools
  verify_pcsclite_for_citrix
  install_citrix
  install_netid
  configure_citrix_optional
  register_netid_in_firefox_profiles
  check_card_reader
  print_summary

  ok "Klart."
}

main "$@"
