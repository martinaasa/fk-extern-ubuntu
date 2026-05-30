#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="/tmp/fkextern-install.log"

# ============================================================
# FK Extern package defaults
# ============================================================

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

APT_UPDATED=0

# ============================================================
# Logging / utility
# ============================================================

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

Flaggor:
  --help                         Visa hjälp
  --yes                          Kör utan bekräftelseprompt
  --dry-run                      Visa planerade steg utan att installera
  --no-reset                     Rensa inte tidigare Citrix/NetiD-installation
  --reset                        Rensa tidigare Citrix/NetiD-installation, default
  --purge-pcscd                  Ta även bort/installera om pcscd och pcsc-tools
  --skip-card-reader-check       Hoppa över pcsc_scan/kortläsarkontroll
  --no-firefox-register          Registrera inte Net iD i Firefox-profiler
  --force-download               Hämta och packa upp FK-paketet på nytt
  --force-unsupported-os         Tillåt körning på ej verifierad Ubuntu-version
  --media-dir PATH               Använd lokalt uppackat media
  --package-url URL              Hämta FK-paket från annan URL

Exempel:
  ./$SCRIPT_NAME
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
      --help|-h)
        usage
        exit 0
        ;;
      --yes|-y)
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
      --media-dir)
        [[ $# -ge 2 ]] || fail "--media-dir kräver sökväg"
        MEDIA_DIR="$2"
        shift 2
        ;;
      --package-url)
        [[ $# -ge 2 ]] || fail "--package-url kräver URL"
        PACKAGE_URL="$2"
        shift 2
        ;;
      *)
        fail "Okänd flagga: $1

Kör:
  ./$SCRIPT_NAME --help"
        ;;
    esac
  done
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Saknar kommando: $1"
}

apt_update_once() {
  if [[ "$APT_UPDATED" -eq 0 ]]; then
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

# ============================================================
# Preflight
# ============================================================

check_ubuntu() {
  log "=== Kontrollerar OS ==="

  if [[ ! -f /etc/os-release ]]; then
    fail "Kan inte läsa /etc/os-release. Endast Ubuntu stöds."
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  log "OS: ${PRETTY_NAME:-okänt}"

  if [[ "${ID:-}" != "ubuntu" ]]; then
    fail "Detta script är endast avsett för Ubuntu.

Identifierat OS:
  ID=${ID:-okänt}
  PRETTY_NAME=${PRETTY_NAME:-okänt}"
  fi

  case "${VERSION_ID:-}" in
    "24.04"|"26.04")
      ok "Ubuntu ${VERSION_ID} är inom avsett testscope."
      ;;
    *)
      if [[ "$FORCE_UNSUPPORTED_OS" == "1" ]]; then
        warn "Ubuntu ${VERSION_ID:-okänd} är inte uttryckligen testad. Fortsätter p.g.a. --force-unsupported-os."
      else
        fail "Ubuntu ${VERSION_ID:-okänd} är inte uttryckligen testad av detta script.

Kör med --force-unsupported-os om du ändå vill fortsätta."
      fi
      ;;
  esac
}

check_deb_firefox_required() {
  log "=== Kontrollerar att Firefox .deb är installerad ==="

  if ! command -v firefox >/dev/null 2>&1; then
    fail "Firefox saknas.

Installera först Firefox som .deb-version:
  https://github.com/martinaasa/ubuntu-firefox-deb-migration"
  fi

  local firefox_cmd firefox_real version owner
  firefox_cmd="$(command -v firefox)"
  firefox_real="$(readlink -f "$firefox_cmd" 2>/dev/null || echo "$firefox_cmd")"
  version="$(firefox --version 2>/dev/null || true)"

  log "firefox command: $firefox_cmd"
  log "firefox realpath: $firefox_real"
  log "firefox version: ${version:-okänd}"

  if [[ "$firefox_real" == /snap/* ]]; then
    fail "Firefox pekar på Snap:
  $firefox_real

Snap-Firefox stöds inte för FK Extern/NetiD.

Installera Firefox som .deb-version:
  https://github.com/martinaasa/ubuntu-firefox-deb-migration"
  fi

  if [[ "$firefox_real" == /app/* ]]; then
    fail "Firefox pekar på Flatpak:
  $firefox_real

Flatpak-Firefox stöds inte för FK Extern/NetiD.

Installera Firefox som .deb-version:
  https://github.com/martinaasa/ubuntu-firefox-deb-migration"
  fi

  if [[ -f /usr/bin/firefox ]] && grep -q "/snap/bin/firefox" /usr/bin/firefox 2>/dev/null; then
    fail "/usr/bin/firefox är en Snap-wrapper.

Installera Firefox som .deb-version:
  https://github.com/martinaasa/ubuntu-firefox-deb-migration"
  fi

  if ! dpkg -s firefox >/dev/null 2>&1; then
    fail "dpkg-paketet firefox är inte installerat.

Installera Firefox som .deb-version:
  https://github.com/martinaasa/ubuntu-firefox-deb-migration"
  fi

  if ! dpkg -S "$firefox_real" >/dev/null 2>&1; then
    fail "Firefox-binären verkar inte ägas av ett deb-paket:
  $firefox_real

Installera Firefox som .deb-version:
  https://github.com/martinaasa/ubuntu-firefox-deb-migration"
  fi

  owner="$(dpkg -S "$firefox_real" | head -n 1)"
  log "dpkg-ägare: $owner"

  ok "Firefox .deb-kontroll OK."
}

# ============================================================
# Media download / discovery
# ============================================================

has_required_media_files() {
  local dir="$1"

  [[ -f "$dir/$CITRIX_CLIENT_DEB" ]] &&
  [[ -f "$dir/$CITRIX_USB_DEB" ]] &&
  [[ -f "$dir/$NETID_ARCHIVE" ]]
}

find_media_dir_under() {
  local root="$1"

  [[ -d "$root" ]] || return 1

  local found
  found="$(
    find "$root" -type f -name "$CITRIX_CLIENT_DEB" -printf '%h\n' 2>/dev/null \
      | while read -r candidate; do
          if has_required_media_files "$candidate"; then
            echo "$candidate"
            break
          fi
        done
  )"

  [[ -n "$found" ]] || return 1
  echo "$found"
}

download_file() {
  local url="$1"
  local output="$2"
  local status_file
  status_file="$(mktemp)"

  rm -f "$output"

  if command -v curl >/dev/null 2>&1; then
    local http_code

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
    [[ -s "$status_file" ]] && log "curl-fel: $(cat "$status_file")"

    rm -f "$status_file"
    return 1
  fi

  if command -v wget >/dev/null 2>&1; then
    if wget \
        --progress=bar:force \
        -O "$output" \
        "$url" 2>"$status_file"; then
      rm -f "$status_file"
      return 0
    fi

    rm -f "$output"

    if grep -q "404" "$status_file"; then
      rm -f "$status_file"
      return 44
    fi

    log "Nedladdning misslyckades från $url"
    [[ -s "$status_file" ]] && log "wget-fel: $(cat "$status_file")"

    rm -f "$status_file"
    return 1
  fi

  fail "Saknar både curl och wget. Kan inte hämta FK Extern-paketet."
}

download_and_extract_media() {
  log "=== Hämtar FK Extern-paket ==="

  apt_install_package "unzip"

  mkdir -p "$DOWNLOAD_DIR"

  if [[ "$FORCE_DOWNLOAD" == "1" ]]; then
    log "FORCE_DOWNLOAD=1, rensar tidigare hämtning/uppackning."
    rm -rf "$DOWNLOAD_DIR" "$EXTRACT_DIR"
    mkdir -p "$DOWNLOAD_DIR" "$EXTRACT_DIR"
  else
    mkdir -p "$EXTRACT_DIR"
  fi

  local zip_path="$DOWNLOAD_DIR/$PACKAGE_ZIP_NAME"
  local urls_to_try=()

  urls_to_try+=("$PACKAGE_URL")
  if [[ "$PACKAGE_URL" != *.zip ]]; then
    urls_to_try+=("${PACKAGE_URL}.zip")
  fi

  if [[ -f "$zip_path" && "$FORCE_DOWNLOAD" != "1" ]]; then
    log "Zip finns redan lokalt: $zip_path"
  else
    local downloaded=0
    local saw_404=0
    local url

    for url in "${urls_to_try[@]}"; do
      log "Försöker hämta: $url"
      log "Paketet är stort. Nedladdningen kan ta en stund."

      set +e
      download_file "$url" "$zip_path"
      local rc=$?
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

    if [[ "$downloaded" -ne 1 ]]; then
      if [[ "$saw_404" -eq 1 ]]; then
        fail "FK Extern-paketet hittades inte på förväntad adress.

Försökte:
$(printf '  %s\n' "${urls_to_try[@]}")

Det som sannolikt har hänt är att paketet har ersatts av en nyare version under:
  $FKEXTERN_BASE_URL/

Scriptet behöver uppdateras med nytt paketnamn, nya filnamn och eventuellt nya versionsnummer för Citrix/NetiD."
      fi

      fail "Kunde inte hämta FK Extern-paketet.

Försökte:
$(printf '  %s\n' "${urls_to_try[@]}")

Kontrollera nätverk, proxy, certifikat eller att adressen är åtkomlig."
    fi
  fi

  [[ -s "$zip_path" ]] || fail "Zip-filen saknas eller är tom: $zip_path"

  if ! unzip -t "$zip_path" >/dev/null 2>&1; then
    fail "Nedladdad fil är inte en giltig zip:
  $zip_path

Antingen pekar URL:en på fel innehåll, eller så har paketet ändrats.
Scriptet behöver kontrolleras och eventuellt uppdateras."
  fi

  log "Packar upp zip till: $EXTRACT_DIR"
  rm -rf "$EXTRACT_DIR"
  mkdir -p "$EXTRACT_DIR"
  unzip -q -o "$zip_path" -d "$EXTRACT_DIR"

  local detected_media_dir
  if detected_media_dir="$(find_media_dir_under "$EXTRACT_DIR")"; then
    MEDIA_DIR="$detected_media_dir"
    ok "Hittade media-katalog i uppackad zip: $MEDIA_DIR"
  else
    fail "Zip-filen hämtades och packades upp, men scriptet hittade inte förväntade installationsfiler.

Förväntade:
  $CITRIX_CLIENT_DEB
  $CITRIX_USB_DEB
  $NETID_ARCHIVE

Uppackat till:
  $EXTRACT_DIR

Det som sannolikt har hänt är att FK har publicerat en nyare version med andra filnamn eller versionsnummer.

Scriptet behöver uppdateras med aktuella filnamn från paketet under:
  $FKEXTERN_BASE_URL/"
  fi
}

ensure_media_dir() {
  log "=== Letar efter FK Extern-media ==="

  if [[ -n "$MEDIA_DIR" ]]; then
    if has_required_media_files "$MEDIA_DIR"; then
      ok "Använder MEDIA_DIR: $MEDIA_DIR"
      return
    fi
    warn "MEDIA_DIR är satt men saknar nödvändiga filer: $MEDIA_DIR"
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if has_required_media_files "$script_dir"; then
    MEDIA_DIR="$script_dir"
    ok "Använder scriptets katalog som media-katalog: $MEDIA_DIR"
    return
  fi

  local detected
  if detected="$(find_media_dir_under "$script_dir")"; then
    MEDIA_DIR="$detected"
    ok "Hittade media under scriptets katalog: $MEDIA_DIR"
    return
  fi

  if [[ "$FORCE_DOWNLOAD" != "1" ]] && detected="$(find_media_dir_under "$EXTRACT_DIR")"; then
    MEDIA_DIR="$detected"
    ok "Hittade media i tidigare uppackning: $MEDIA_DIR"
    return
  fi

  log "Hittade inte media lokalt. Hämtar från FK."
  download_and_extract_media
}

require_media_file() {
  local filename="$1"
  [[ -f "$MEDIA_DIR/$filename" ]] || fail "Saknar fil: $MEDIA_DIR/$filename"
}

copy_media_to_tmp() {
  local src="$1"
  local dst_dir="/tmp/ubuntu_extern2605_media"
  local dst="$dst_dir/$(basename "$src")"

  run sudo mkdir -p "$dst_dir"
  run sudo cp -f "$src" "$dst"
  run sudo chmod 0644 "$dst"

  echo "$dst"
}

get_deb_package_name() {
  local deb_path="$1"

  if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb -f "$deb_path" Package 2>/dev/null || true
  fi
}

apt_install_deb() {
  local original_deb_path="$1"
  local package_hint="$2"

  [[ -f "$original_deb_path" ]] || fail "Saknar deb-paket: $original_deb_path"

  local package_name
  package_name="$(get_deb_package_name "$original_deb_path")"
  [[ -n "$package_name" ]] || package_name="$package_hint"

  if dpkg -s "$package_name" >/dev/null 2>&1; then
    ok "$package_name är redan installerat."
    return
  fi

  local deb_path
  deb_path="$(copy_media_to_tmp "$original_deb_path")"

  log "Installerar deb-paket: $deb_path"
  log "Om Citrix frågar om AppProtection/DeviceTrust/EPAClient: välj no."

  run sudo apt-get install -y "$deb_path"
}

# ============================================================
# Reset
# ============================================================

reset_existing_installation() {
  log "=== Rensar tidigare FK Extern-installation ==="

  pkill firefox 2>/dev/null || true
  pkill firefox-bin 2>/dev/null || true
  sleep 1

  log "Stoppar NetiD-tjänster om de finns..."
  run sudo systemctl stop netid 2>/dev/null || true
  run sudo systemctl stop netid.service 2>/dev/null || true
  run sudo systemctl stop netid-monitor 2>/dev/null || true
  run sudo systemctl stop netid-monitor.service 2>/dev/null || true
  run sudo systemctl stop netid-service 2>/dev/null || true
  run sudo systemctl stop netid-service.service 2>/dev/null || true

  log "Tar bort Citrix-paket..."
  apt_purge_if_installed "ctxusb"
  apt_purge_if_installed "icaclient"

  if [[ "$PURGE_PCSCD" == "1" ]]; then
    log "PURGE_PCSCD=1, tar även bort pcscd/pcsc-tools."
    run sudo systemctl stop pcscd 2>/dev/null || true
    apt_purge_if_installed "pcsc-tools"
    apt_purge_if_installed "pcscd"
  else
    log "Behåller pcscd installerat."
  fi

  log "Tar bort NetiD-filer..."
  remove_path_if_exists "/lib/netid"
  remove_path_if_exists "/usr/lib/netid"
  remove_path_if_exists "/usr/share/netid"
  remove_path_if_exists "/usr/local/lib/netid"
  remove_path_if_exists "/etc/netid"
  remove_path_if_exists "/opt/netid"
  remove_path_if_exists "/usr/bin/netid"
  remove_path_if_exists "/usr/local/bin/netid"

  remove_path_if_exists "/etc/systemd/system/netid.service"
  remove_path_if_exists "/etc/systemd/system/netid-monitor.service"
  remove_path_if_exists "/etc/systemd/system/netid-service.service"
  remove_path_if_exists "/usr/lib/systemd/system/netid.service"
  remove_path_if_exists "/usr/lib/systemd/system/netid-monitor.service"
  remove_path_if_exists "/usr/lib/systemd/system/netid-service.service"

  remove_path_if_exists "/etc/xdg/autostart/netid.desktop"
  remove_path_if_exists "/usr/share/applications/netid.desktop"
  remove_path_if_exists "/tmp/ubuntu_extern2605_media"

  run sudo systemctl daemon-reload || true
  run sudo apt-get autoremove -y || true

  ok "Rensning klar."
}

# ============================================================
# Installation
# ============================================================

install_pcscd_and_reader_tools() {
  log "=== Installerar pcscd och kortläsarverktyg ==="

  apt_install_package "pcscd"
  apt_install_package "pcsc-tools"
  apt_install_package "libccid"
  apt_install_package "libnss3-tools"
  apt_install_package "python3"

  log "Aktiverar pcscd..."
  run sudo systemctl enable pcscd

  log "Startar om pcscd..."
  run sudo systemctl restart pcscd

  if systemctl is-active --quiet pcscd; then
    ok "pcscd är aktiv."
  else
    sudo systemctl status pcscd --no-pager || true
    fail "pcscd är inte aktiv."
  fi
}

install_citrix() {
  log "=== Installerar Citrix Workspace App och USB-stöd ==="

  require_media_file "$CITRIX_CLIENT_DEB"
  require_media_file "$CITRIX_USB_DEB"

  apt_install_deb "$MEDIA_DIR/$CITRIX_CLIENT_DEB" "icaclient"
  apt_install_deb "$MEDIA_DIR/$CITRIX_USB_DEB" "ctxusb"

  ok "Citrix-installation klar."
}

install_netid() {
  log "=== Installerar NetiD Client ==="

  require_media_file "$NETID_ARCHIVE"
  require_cmd tar
  require_cmd find

  local tmp_extract_dir
  tmp_extract_dir="$(mktemp -d)"

  log "Packar upp $NETID_ARCHIVE..."
  tar -xzf "$MEDIA_DIR/$NETID_ARCHIVE" -C "$tmp_extract_dir"

  local installer_dir
  installer_dir="$(find "$tmp_extract_dir" -maxdepth 3 -type f -name install -printf '%h\n' | head -n 1)"

  if [[ -z "$installer_dir" ]]; then
    rm -rf "$tmp_extract_dir"
    fail "Hittade ingen NetiD-installerare med namnet install."
  fi

  log "Kör NetiD-installeraren från $installer_dir"
  log "Svarar Y på NSS/PKCS#11-registrering om installern frågar."

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] skulle köra NetiD-installeraren"
  else
    (
      cd "$installer_dir"
      printf 'y\n' | sudo ./install
    )
  fi

  rm -rf "$tmp_extract_dir"

  if [[ "$DRY_RUN" != "1" ]]; then
    [[ -f "$NETID_LIB" ]] || fail "NetiD-installationen kördes, men $NETID_LIB hittades inte."
  fi

  ok "NetiD installerat."
}

configure_citrix_smartcard() {
  log "=== Konfigurerar Citrix SmartCard/NetiD ==="

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] skulle konfigurera Citrix SmartCard/NetiD"
    return
  fi

  [[ -f "$NETID_LIB" ]] || fail "Saknar NetiD-bibliotek: $NETID_LIB"

  local module_ini="/opt/Citrix/ICAClient/config/module.ini"
  local authman_xml="/opt/Citrix/ICAClient/config/AuthManConfig.xml"
  local scard_json="/opt/Citrix/ICAClient/config/scardConfig.json"
  local usb_conf="/opt/Citrix/ICAClient/usb.conf"
  local backup_suffix
  backup_suffix="$(date +%Y%m%d-%H%M%S)"

  for file in "$module_ini" "$authman_xml" "$scard_json" "$usb_conf"; do
    if [[ -f "$file" ]]; then
      sudo cp -a "$file" "$file.bak.$backup_suffix"
      log "Backup: $file.bak.$backup_suffix"
    else
      warn "Saknar Citrix-konfigfil: $file"
    fi
  done

  if [[ -f "$module_ini" ]]; then
    sudo sed -i \
      -e 's/^DriverName *=.*/DriverName = VDSCARDV2.DLL/' \
      -e 's/^PCSCLibraryName *=.*/PCSCLibraryName = libpcsclite.so/' \
      -e 's/^UseInternalSCard *=.*/UseInternalSCard = TRUE/' \
      "$module_ini"
  fi

  if [[ -f "$authman_xml" ]]; then
    sudo python3 - "$authman_xml" "$NETID_LIB" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
netid = sys.argv[2]
text = path.read_text(encoding="utf-8", errors="replace")

marker = "<key>PKCS11module</key>"
idx = text.find(marker)
if idx == -1:
    raise SystemExit("PKCS11module key not found")

value_start = text.find("<value>", idx)
value_end = text.find("</value>", value_start)

if value_start == -1 or value_end == -1:
    raise SystemExit("PKCS11module value not found")

value_start += len("<value>")
text = text[:value_start] + netid + text[value_end:]

path.write_text(text, encoding="utf-8")
PY
  fi

  if [[ -f "$scard_json" ]]; then
    sudo python3 - "$scard_json" "$NETID_LIB" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
netid = sys.argv[2]

data = json.loads(path.read_text(encoding="utf-8"))
data["DefaultPKCS11Lib"] = netid

for key in ("PKCS11Modules", "PKCS11ModuleList", "Modules"):
    value = data.get(key)
    if isinstance(value, list):
        for item in value:
            if isinstance(item, dict):
                name = str(item.get("Name", item.get("name", "")))
                lib = item.get("PKCS11Lib") or item.get("Library") or item.get("library")
                if name == "Net iD" or lib in ("/usr/lib/netid/libnetid.so", "/lib/netid/libnetid.so"):
                    if "PKCS11Lib" in item:
                        item["PKCS11Lib"] = netid
                    elif "Library" in item:
                        item["Library"] = netid
                    elif "library" in item:
                        item["library"] = netid
                    else:
                        item["PKCS11Lib"] = netid

path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
  fi

  if [[ -f "$usb_conf" ]]; then
    if ! grep -Eq '^DENY:[[:space:]]+class=0b' "$usb_conf"; then
      log "Lägger till DENY för smartcard i Citrix USB-config."
      local tmp
      tmp="$(mktemp)"
      {
        echo "DENY:  class=0b # Smartcard readers should use smart card remoting, not generic USB"
        cat "$usb_conf"
      } > "$tmp"
      sudo cp "$tmp" "$usb_conf"
      rm -f "$tmp"
    else
      log "Citrix USB-config har redan DENY för class=0b."
    fi
  fi

  log "Verifierar Citrix SmartCard-konfig:"
  grep -n -A8 -B2 '\[SmartCard\]' "$module_ini" 2>/dev/null | tee -a "$LOG_FILE" || true
  grep -n -A3 -B3 'PKCS11module' "$authman_xml" 2>/dev/null | tee -a "$LOG_FILE" || true
  grep -n -A3 -B3 'DefaultPKCS11Lib' "$scard_json" 2>/dev/null | tee -a "$LOG_FILE" || true
  grep -n 'class=0b' "$usb_conf" 2>/dev/null | tee -a "$LOG_FILE" || true

  ok "Citrix SmartCard/NetiD-konfiguration klar."
}

# ============================================================
# Firefox NSS / NetiD
# ============================================================

remove_existing_netid_from_profile() {
  local profile_dir="$1"

  if modutil -dbdir "sql:$profile_dir" -list 2>/dev/null | grep -q "$NETID_MODULE_NAME"; then
    log "Tar bort befintlig Net iD-registrering i: $profile_dir"
    modutil -force -dbdir "sql:$profile_dir" -delete "$NETID_MODULE_NAME" || true
  fi
}

register_netid_in_profile() {
  local profile_dir="$1"

  [[ -d "$profile_dir" ]] || return

  log "Registrerar NetiD i Firefox-profil: $profile_dir"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] skulle registrera NetiD i profilen"
    return
  fi

  if [[ ! -f "$profile_dir/cert9.db" ]]; then
    log "cert9.db saknas, skapar NSS-db."
    modutil -force -dbdir "sql:$profile_dir" -create || true
  fi

  remove_existing_netid_from_profile "$profile_dir"

  modutil -force \
    -dbdir "sql:$profile_dir" \
    -add "$NETID_MODULE_NAME" \
    -libfile "$NETID_LIB" \
    -mechanisms FRIENDLY || true

  if modutil -dbdir "sql:$profile_dir" -list 2>/dev/null | grep -q "$NETID_MODULE_NAME"; then
    ok "NetiD finns registrerad i profilen."
    modutil -dbdir "sql:$profile_dir" -list | grep -A40 "$NETID_MODULE_NAME" | tee -a "$LOG_FILE" || true
  else
    warn "NetiD kunde inte verifieras i profilen: $profile_dir"
  fi
}

register_netid_in_firefox_profiles() {
  log "=== Registrerar NetiD i deb-Firefox-profiler ==="

  if [[ "$REGISTER_NETID_IN_FIREFOX" != "1" ]]; then
    log "Hoppar över Firefox-registrering."
    return
  fi

  if [[ "$DRY_RUN" != "1" ]]; then
    [[ -f "$NETID_LIB" ]] || fail "Saknar $NETID_LIB"
    require_cmd modutil
  fi

  pkill firefox 2>/dev/null || true
  pkill firefox-bin 2>/dev/null || true
  sleep 1

  local firefox_root="$HOME/.mozilla/firefox"
  mkdir -p "$firefox_root"

  local profile_dirs=()
  local profile_dir

  if [[ -f "$firefox_root/profiles.ini" ]]; then
    while IFS= read -r profile_path; do
      [[ -z "$profile_path" ]] && continue

      if [[ "$profile_path" = /* ]]; then
        profile_dir="$profile_path"
      else
        profile_dir="$firefox_root/$profile_path"
      fi

      [[ -d "$profile_dir" ]] && profile_dirs+=("$profile_dir")
    done < <(awk -F= '/^Path=/{print $2}' "$firefox_root/profiles.ini")
  fi

  while IFS= read -r certdb; do
    profile_dirs+=("$(dirname "$certdb")")
  done < <(find "$firefox_root" -maxdepth 2 -type f -name cert9.db 2>/dev/null)

  if [[ "${#profile_dirs[@]}" -eq 0 ]]; then
    warn "Hittade ingen Firefox-profil. Starta Firefox en gång och kör scriptet igen."
    return
  fi

  printf '%s\n' "${profile_dirs[@]}" | sort -u | while IFS= read -r profile_dir; do
    register_netid_in_profile "$profile_dir"
  done
}

# ============================================================
# Card reader check
# ============================================================

check_card_reader() {
  log "=== Läser in/kontrollerar kortläsare ==="

  if [[ "$CHECK_CARD_READER" != "1" ]]; then
    log "Hoppar över kortläsarkontroll."
    return
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] skulle starta om pcscd och köra pcsc_scan"
    return
  fi

  sudo systemctl restart pcscd
  sleep 2

  if command -v pcsc_scan >/dev/null 2>&1; then
    log "Kör pcsc_scan i max 8 sekunder. Timeout är förväntat eftersom pcsc_scan annars fortsätter lyssna..."
    timeout 8 pcsc_scan 2>&1 | tee -a "$LOG_FILE" || true
  else
    warn "pcsc_scan saknas."
  fi

  if [[ -f "$NETID_LIB" ]] && command -v modutil >/dev/null 2>&1; then
    log "Kontrollerar NetiD-slots i Firefox-profiler..."

    local any_profile=0
    while IFS= read -r certdb; do
      any_profile=1
      local profile_dir
      profile_dir="$(dirname "$certdb")"

      log "NSS-listning för: $profile_dir"
      modutil -dbdir "sql:$profile_dir" -list 2>/dev/null | grep -A50 "$NETID_MODULE_NAME" | tee -a "$LOG_FILE" || true
    done < <(find "$HOME/.mozilla/firefox" -maxdepth 2 -type f -name cert9.db 2>/dev/null)

    [[ "$any_profile" -eq 1 ]] || warn "Ingen Firefox NSS-db hittades för slot-kontroll."
  fi
}

# ============================================================
# UX
# ============================================================

print_preflight() {
  cat <<EOF

============================================================
Preflight
============================================================

Detta script installerar FK Extern-komponenter för Ubuntu.

Avsett för:
  anställda/konsulter på Försäkringskassan

Inte avsett för:
  andra organisationer
  andra distributioner än Ubuntu
  generell Citrix/NetiD-support

Support:
  ingen support ges på scriptet

Firefox:
  måste redan vara .deb
  installeras inte av detta script
  se: https://github.com/martinaasa/ubuntu-firefox-deb-migration

Media:
  PACKAGE_URL=$PACKAGE_URL
  MEDIA_DIR=${MEDIA_DIR:-automatisk}

Val:
  RESET_BEFORE_INSTALL=$RESET_BEFORE_INSTALL
  PURGE_PCSCD=$PURGE_PCSCD
  REGISTER_NETID_IN_FIREFOX=$REGISTER_NETID_IN_FIREFOX
  CHECK_CARD_READER=$CHECK_CARD_READER
  FORCE_DOWNLOAD=$FORCE_DOWNLOAD
  DRY_RUN=$DRY_RUN

Logg:
  $LOG_FILE

============================================================

EOF
}

confirm_continue() {
  if [[ "$ASSUME_YES" == "1" || "$DRY_RUN" == "1" ]]; then
    return
  fi

  read -r -p "Fortsätta? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES|Ja|ja)
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

Media:
  $MEDIA_DIR

Firefox:
  $(command -v firefox 2>/dev/null || true)
  $(readlink -f "$(command -v firefox)" 2>/dev/null || true)
  $(firefox --version 2>/dev/null || true)

NetiD:
  $NETID_LIB

Kontrollera i Firefox:
  Settings
  Privacy & Security
  Certificates
  Security Devices

Där ska Net iD synas.

Kortläsare:
  Kontrollera loggen för pcsc_scan och NetiD-slots.

Citrix:
  SmartCard-konfiguration ska peka på:
    $NETID_LIB

Viktigt:
  Starta om datorn innan första anslutning till Citrix/remote desktop.

Logg:
  $LOG_FILE

============================================================

EOF
}

main() {
  parse_args "$@"

  log "Startar $SCRIPT_NAME"
  log "Loggfil: $LOG_FILE"

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
  check_deb_firefox_required
  ensure_media_dir
  log "Använder media-katalog: $MEDIA_DIR"

  if [[ "$RESET_BEFORE_INSTALL" == "1" ]]; then
    reset_existing_installation
  else
    log "Hoppar över rensning."
  fi

  install_pcscd_and_reader_tools
  install_citrix
  install_netid
  configure_citrix_smartcard
  register_netid_in_firefox_profiles
  check_card_reader
  print_summary

  ok "Klart."
}

main "$@"
