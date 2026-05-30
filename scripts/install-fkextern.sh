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
CONFIGURE_CITRIX_SMARTCARD=0
SET_CITRIX_PCSCLIBRARY_FULL_PATH=0
DISABLE_CITRIX_USB_SMARTCARD=0
APT_UPDATED=0

log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
ok(){ log "[OK] $*"; }
warn(){ log "[WARN] $*"; }
fail(){ echo; log "[FEL] $*"; exit 1; }
run(){ if [[ "$DRY_RUN" == 1 ]]; then log "[dry-run] $*"; else "$@"; fi; }
require_cmd(){ command -v "$1" >/dev/null 2>&1 || fail "Saknar kommando: $1"; }

usage(){ cat <<HELP
Användning: $SCRIPT_NAME [flaggor]

Installerar FK Extern-komponenter på Ubuntu.

Krav:
  Firefox måste redan vara riktig .deb. Snap/Flatpak stöds inte.
  För Firefox .deb: https://github.com/martinaasa/ubuntu-firefox-deb-migration

Vanliga flaggor:
  --yes, --dry-run, --no-reset, --reset, --force-download
  --media-dir PATH, --package-url URL, --skip-card-reader-check
  --force-unsupported-os, --purge-pcscd, --no-firefox-register

Felsökningsflaggor, inte default:
  --reset-user-citrix-cache
  --configure-citrix-smartcard
  --set-citrix-pcsclibrary-full-path
  --disable-citrix-usb-smartcard
HELP
}

parse_args(){
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) usage; exit 0;;
      --yes|-y) ASSUME_YES=1; shift;;
      --dry-run) DRY_RUN=1; shift;;
      --no-reset) RESET_BEFORE_INSTALL=0; shift;;
      --reset) RESET_BEFORE_INSTALL=1; shift;;
      --purge-pcscd) PURGE_PCSCD=1; shift;;
      --skip-card-reader-check) CHECK_CARD_READER=0; shift;;
      --no-firefox-register) REGISTER_NETID_IN_FIREFOX=0; shift;;
      --force-download) FORCE_DOWNLOAD=1; shift;;
      --force-unsupported-os) FORCE_UNSUPPORTED_OS=1; shift;;
      --reset-user-citrix-cache) RESET_USER_CITRIX_CACHE=1; shift;;
      --configure-citrix-smartcard) CONFIGURE_CITRIX_SMARTCARD=1; shift;;
      --set-citrix-pcsclibrary-full-path) SET_CITRIX_PCSCLIBRARY_FULL_PATH=1; shift;;
      --disable-citrix-usb-smartcard) DISABLE_CITRIX_USB_SMARTCARD=1; shift;;
      --media-dir) [[ $# -ge 2 ]] || fail "--media-dir kräver sökväg"; MEDIA_DIR="$2"; shift 2;;
      --package-url) [[ $# -ge 2 ]] || fail "--package-url kräver URL"; PACKAGE_URL="$2"; shift 2;;
      *) fail "Okänd flagga: $1";;
    esac
  done
}

apt_update_once(){ [[ "$APT_UPDATED" == 0 ]] && { log "Kör apt-get update..."; run sudo apt-get update; APT_UPDATED=1; }; }
apt_install(){ dpkg -s "$1" >/dev/null 2>&1 && ok "$1 är redan installerat." && return; apt_update_once; log "Installerar $1..."; run sudo apt-get install -y "$1"; }
apt_purge_if_installed(){ dpkg -s "$1" >/dev/null 2>&1 && { log "Tar bort paket: $1"; run sudo apt-get purge -y "$1" || true; } || log "$1 är inte installerat."; }

check_ubuntu(){
  log "=== Kontrollerar OS ==="
  [[ -f /etc/os-release ]] || fail "Kan inte läsa /etc/os-release. Endast Ubuntu stöds."
  . /etc/os-release
  log "OS: ${PRETTY_NAME:-okänt}"
  [[ "${ID:-}" == ubuntu ]] || fail "Detta script är endast avsett för Ubuntu. Identifierat: ${PRETTY_NAME:-okänt}"
  case "${VERSION_ID:-}" in 24.04|26.04) ok "Ubuntu ${VERSION_ID} är inom avsett testscope.";; *) [[ "$FORCE_UNSUPPORTED_OS" == 1 ]] && warn "Ubuntu ${VERSION_ID:-okänd} är inte testad, fortsätter." || fail "Ubuntu ${VERSION_ID:-okänd} är inte uttryckligen testad. Använd --force-unsupported-os för att fortsätta.";; esac
}

check_firefox_deb(){
  log "=== Kontrollerar att Firefox .deb är installerad ==="
  command -v firefox >/dev/null 2>&1 || fail "Firefox saknas. Installera Firefox .deb: https://github.com/martinaasa/ubuntu-firefox-deb-migration"
  local cmd real ver
  cmd=$(command -v firefox); real=$(readlink -f "$cmd" 2>/dev/null || echo "$cmd"); ver=$(firefox --version 2>/dev/null || true)
  log "firefox command: $cmd"; log "firefox realpath: $real"; log "firefox version: ${ver:-okänd}"
  [[ "$real" != /snap/* ]] || fail "Firefox pekar på Snap. Installera .deb-version först."
  [[ "$real" != /app/* ]] || fail "Firefox pekar på Flatpak. Installera .deb-version först."
  if [[ -f /usr/bin/firefox ]] && grep -q /snap/bin/firefox /usr/bin/firefox 2>/dev/null; then fail "/usr/bin/firefox är en Snap-wrapper. Installera .deb-version först."; fi
  dpkg -s firefox >/dev/null 2>&1 || fail "dpkg-paketet firefox är inte installerat. Installera .deb-version först."
  dpkg -S "$real" >/dev/null 2>&1 || fail "Firefox-binären verkar inte ägas av ett deb-paket: $real"
  ok "Firefox .deb-kontroll OK."
}

has_media(){ [[ -f "$1/$CITRIX_CLIENT_DEB" && -f "$1/$CITRIX_USB_DEB" && -f "$1/$NETID_ARCHIVE" ]]; }
find_media(){ find "$1" -type f -name "$CITRIX_CLIENT_DEB" -printf '%h\n' 2>/dev/null | while read -r d; do has_media "$d" && { echo "$d"; break; }; done; }

download_file(){
  local url="$1" out="$2" status code
  status=$(mktemp); rm -f "$out"
  if command -v curl >/dev/null 2>&1; then
    code=$(curl --fail --location --progress-bar --output "$out" --write-out "%{http_code}" "$url" 2>"$status" || true)
    [[ "$code" == 200 ]] && { rm -f "$status"; return 0; }
    rm -f "$out"; [[ "$code" == 404 ]] && { rm -f "$status"; return 44; }
    log "Nedladdning misslyckades från $url"; log "HTTP-status: ${code:-okänd}"; [[ -s "$status" ]] && log "curl-fel: $(cat "$status")"; rm -f "$status"; return 1
  fi
  if command -v wget >/dev/null 2>&1; then
    wget --progress=bar:force -O "$out" "$url" 2>"$status" && { rm -f "$status"; return 0; }
    rm -f "$out"; grep -q 404 "$status" && { rm -f "$status"; return 44; }
    log "Nedladdning misslyckades från $url"; [[ -s "$status" ]] && log "wget-fel: $(cat "$status")"; rm -f "$status"; return 1
  fi
  fail "Saknar både curl och wget."
}

fetch_media(){
  log "=== Hämtar FK Extern-paket ==="
  apt_install unzip
  [[ "$FORCE_DOWNLOAD" == 1 ]] && rm -rf "$DOWNLOAD_DIR" "$EXTRACT_DIR"
  mkdir -p "$DOWNLOAD_DIR" "$EXTRACT_DIR"
  local zip="$DOWNLOAD_DIR/$PACKAGE_ZIP_NAME" urls=("$PACKAGE_URL") okdl=0 saw404=0
  [[ "$PACKAGE_URL" != *.zip ]] && urls+=("${PACKAGE_URL}.zip")
  if [[ -f "$zip" && "$FORCE_DOWNLOAD" != 1 ]]; then log "Zip finns redan lokalt: $zip"; else
    for u in "${urls[@]}"; do
      log "Försöker hämta: $u"; log "Paketet är stort. Nedladdningen kan ta en stund."
      set +e; download_file "$u" "$zip"; rc=$?; set -e
      [[ $rc -eq 0 ]] && { okdl=1; ok "Hämtning lyckades: $u"; break; }
      [[ $rc -eq 44 ]] && { saw404=1; warn "Paketet hittades inte på: $u"; continue; }
    done
    [[ $okdl -eq 1 ]] || { [[ $saw404 -eq 1 ]] && fail "FK Extern-paketet hittades inte. Sannolikt har en nyare version ersatt paketet under $FKEXTERN_BASE_URL/. Scriptet behöver uppdateras."; fail "Kunde inte hämta FK Extern-paketet."; }
  fi
  [[ -s "$zip" ]] || fail "Zip-filen saknas eller är tom: $zip"
  unzip -t "$zip" >/dev/null 2>&1 || fail "Nedladdad fil är inte en giltig zip: $zip"
  rm -rf "$EXTRACT_DIR"; mkdir -p "$EXTRACT_DIR"; unzip -q -o "$zip" -d "$EXTRACT_DIR"
  MEDIA_DIR=$(find_media "$EXTRACT_DIR" | head -n1)
  [[ -n "$MEDIA_DIR" ]] || fail "Zippen saknar förväntade filer: $CITRIX_CLIENT_DEB, $CITRIX_USB_DEB, $NETID_ARCHIVE. Scriptet behöver uppdateras."
  ok "Hittade media-katalog: $MEDIA_DIR"
}

ensure_media(){
  log "=== Letar efter FK Extern-media ==="
  if [[ -n "$MEDIA_DIR" ]]; then has_media "$MEDIA_DIR" && { ok "Använder MEDIA_DIR: $MEDIA_DIR"; return; }; warn "MEDIA_DIR saknar filer: $MEDIA_DIR"; fi
  local sd; sd=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  has_media "$sd" && { MEDIA_DIR="$sd"; ok "Använder scriptets katalog: $MEDIA_DIR"; return; }
  MEDIA_DIR=$(find_media "$sd" | head -n1 || true); [[ -n "$MEDIA_DIR" ]] && { ok "Hittade media under scriptets katalog: $MEDIA_DIR"; return; }
  [[ "$FORCE_DOWNLOAD" != 1 ]] && MEDIA_DIR=$(find_media "$EXTRACT_DIR" | head -n1 || true) && [[ -n "$MEDIA_DIR" ]] && { ok "Hittade media i tidigare uppackning: $MEDIA_DIR"; return; }
  fetch_media
}

copy_deb(){ local src="$1" dst_dir=/tmp/ubuntu_extern2605_media; run sudo mkdir -p "$dst_dir"; run sudo cp -f "$src" "$dst_dir/$(basename "$src")"; run sudo chmod 0644 "$dst_dir/$(basename "$src")"; echo "$dst_dir/$(basename "$src")"; }
install_deb(){ local deb="$1" hint="$2" pkg; [[ -f "$deb" ]] || fail "Saknar deb-paket: $deb"; pkg=$(dpkg-deb -f "$deb" Package 2>/dev/null || echo "$hint"); dpkg -s "$pkg" >/dev/null 2>&1 && { ok "$pkg är redan installerat."; return; }; local tmp; tmp=$(copy_deb "$deb"); log "Installerar deb-paket: $tmp"; log "Om Citrix frågar om AppProtection/DeviceTrust/EPAClient: välj no."; run sudo apt-get install -y "$tmp"; }

reset_install(){
  log "=== Rensar tidigare FK Extern-installation ==="
  pkill firefox 2>/dev/null || true; pkill firefox-bin 2>/dev/null || true; pkill -f '/opt/Citrix/ICAClient/adapter|ctxwebhelper|icasessionmgr|AuthManagerDaemon|ServiceRecord|selfservice' 2>/dev/null || true; pkill wfica 2>/dev/null || true; sleep 1
  apt_purge_if_installed ctxusb; apt_purge_if_installed icaclient
  if [[ "$PURGE_PCSCD" == 1 ]]; then run sudo systemctl stop pcscd 2>/dev/null || true; apt_purge_if_installed pcsc-tools; apt_purge_if_installed pcscd; fi
  for p in /lib/netid /usr/lib/netid /usr/share/netid /usr/local/lib/netid /etc/netid /opt/netid /usr/bin/netid /usr/local/bin/netid /etc/systemd/system/netid.service /etc/systemd/system/netid-monitor.service /etc/systemd/system/netid-service.service /usr/lib/systemd/system/netid.service /usr/lib/systemd/system/netid-monitor.service /usr/lib/systemd/system/netid-service.service /etc/xdg/autostart/netid.desktop /usr/share/applications/netid.desktop /tmp/ubuntu_extern2605_media; do [[ -e "$p" || -L "$p" ]] && { log "Tar bort: $p"; run sudo rm -rf "$p"; } || true; done
  run sudo systemctl daemon-reload || true; run sudo apt-get autoremove -y || true; ok "Rensning klar."
}

reset_user_cache(){ [[ "$RESET_USER_CITRIX_CACHE" != 1 ]] && { log "Behåller användarens Citrix-cache ~/.ICAClient."; return; }; [[ -d "$HOME/.ICAClient" ]] && { dst="$HOME/.ICAClient.bak.$(date +%Y%m%d-%H%M%S)"; log "Flyttar ~/.ICAClient till $dst"; run mv "$HOME/.ICAClient" "$dst"; } || log "~/.ICAClient finns inte."; }

install_pcsc(){ log "=== Installerar pcscd och kortläsarverktyg ==="; apt_install pcscd; apt_install pcsc-tools; apt_install libccid; apt_install libnss3-tools; apt_install libpcsclite-dev; apt_install python3; run sudo systemctl enable pcscd; run sudo systemctl restart pcscd; systemctl is-active --quiet pcscd && ok "pcscd är aktiv." || fail "pcscd är inte aktiv."; }
verify_pcsclite(){ log "=== Verifierar libpcsclite för Citrix ==="; [[ "$DRY_RUN" == 1 ]] && return; sudo ldconfig; ldconfig -p | grep -q 'libpcsclite\.so ' && { ok "libpcsclite.so finns i linker-cache."; ldconfig -p | grep 'libpcsclite\.so' | tee -a "$LOG_FILE" || true; } || fail "Citrix behöver libpcsclite.so. Installera libpcsclite-dev."; }
install_citrix(){ log "=== Installerar Citrix Workspace App och USB-stöd ==="; install_deb "$MEDIA_DIR/$CITRIX_CLIENT_DEB" icaclient; install_deb "$MEDIA_DIR/$CITRIX_USB_DEB" ctxusb; ok "Citrix-installation klar."; }
install_netid(){ log "=== Installerar NetiD Client ==="; local tmp inst; tmp=$(mktemp -d); tar -xzf "$MEDIA_DIR/$NETID_ARCHIVE" -C "$tmp"; inst=$(find "$tmp" -maxdepth 3 -type f -name install -printf '%h\n' | head -n1); [[ -n "$inst" ]] || fail "Hittade ingen NetiD-installerare"; [[ "$DRY_RUN" == 1 ]] && log "[dry-run] skulle köra NetiD-installeraren" || (cd "$inst" && printf 'y\n' | sudo ./install); rm -rf "$tmp"; [[ "$DRY_RUN" == 1 || -f "$NETID_LIB" ]] || fail "NetiD installerades men $NETID_LIB saknas"; ok "NetiD installerat."; }

configure_citrix_optional(){
  if [[ "$CONFIGURE_CITRIX_SMARTCARD" != 1 && "$SET_CITRIX_PCSCLIBRARY_FULL_PATH" != 1 && "$DISABLE_CITRIX_USB_SMARTCARD" != 1 ]]; then log "Hoppar över ändring av Citrix-konfig. Standardkonfiguration lämnas orörd."; return; fi
  log "=== Felsökningsläge: ändrar Citrix-konfig ==="
  [[ "$DRY_RUN" == 1 ]] && return
  local module=/opt/Citrix/ICAClient/config/module.ini auth=/opt/Citrix/ICAClient/config/AuthManConfig.xml scard=/opt/Citrix/ICAClient/config/scardConfig.json usb=/opt/Citrix/ICAClient/usb.conf bak; bak=$(date +%Y%m%d-%H%M%S)
  for f in "$module" "$auth" "$scard" "$usb"; do [[ -f "$f" ]] && sudo cp -a "$f" "$f.bak.$bak"; done
  if [[ "$CONFIGURE_CITRIX_SMARTCARD" == 1 ]]; then
    [[ -f "$module" ]] && sudo sed -i -e 's/^DriverName *=.*/DriverName = VDSCARDV2.DLL/' -e 's/^PCSCLibraryName *=.*/PCSCLibraryName = libpcsclite.so/' -e 's/^UseInternalSCard *=.*/UseInternalSCard = TRUE/' "$module"
    [[ -f "$auth" ]] && sudo python3 - "$auth" "$NETID_LIB" <<'PY2'
import sys
from pathlib import Path
p=Path(sys.argv[1]); lib=sys.argv[2]; s=p.read_text(encoding='utf-8',errors='replace'); m='<key>PKCS11module</key>'; i=s.find(m)
if i!=-1:
    a=s.find('<value>',i); b=s.find('</value>',a)
    if a!=-1 and b!=-1: p.write_text(s[:a+7]+lib+s[b:],encoding='utf-8')
PY2
    [[ -f "$scard" ]] && sudo python3 - "$scard" "$NETID_LIB" <<'PY3'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); lib=sys.argv[2]; d=json.loads(p.read_text(encoding='utf-8')); d['DefaultPKCS11Lib']=lib; p.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
PY3
  fi
  if [[ "$SET_CITRIX_PCSCLIBRARY_FULL_PATH" == 1 && -f "$module" ]]; then pcsc=$(ldconfig -p | awk '/libpcsclite\.so /{print $NF; exit}'); [[ -n "$pcsc" ]] && sudo sed -i "s#^PCSCLibraryName *=.*#PCSCLibraryName = $pcsc#" "$module"; fi
  if [[ "$DISABLE_CITRIX_USB_SMARTCARD" == 1 && -f "$usb" ]] && ! grep -Eq '^DENY:[[:space:]]+class=0b' "$usb"; then tmp=$(mktemp); { echo 'DENY:  class=0b # Smartcard readers should use smart card remoting, not generic USB'; cat "$usb"; } > "$tmp"; sudo cp "$tmp" "$usb"; rm -f "$tmp"; fi
  ok "Citrix-konfigändring klar."
}

register_profile(){ local p="$1"; [[ -d "$p" ]] || return; log "Registrerar NetiD i Firefox-profil: $p"; [[ "$DRY_RUN" == 1 ]] && return; [[ -f "$p/cert9.db" ]] || modutil -force -dbdir "sql:$p" -create || true; modutil -dbdir "sql:$p" -list 2>/dev/null | grep -q "$NETID_MODULE_NAME" && modutil -force -dbdir "sql:$p" -delete "$NETID_MODULE_NAME" || true; modutil -force -dbdir "sql:$p" -add "$NETID_MODULE_NAME" -libfile "$NETID_LIB" -mechanisms FRIENDLY || true; modutil -dbdir "sql:$p" -list 2>/dev/null | grep -q "$NETID_MODULE_NAME" && ok "Net iD registrerad i $p" || warn "Net iD kunde inte verifieras i $p"; }
register_firefox(){ log "=== Registrerar NetiD i deb-Firefox-profiler ==="; [[ "$REGISTER_NETID_IN_FIREFOX" == 1 ]] || return; [[ "$DRY_RUN" == 1 ]] || require_cmd modutil; pkill firefox 2>/dev/null || true; pkill firefox-bin 2>/dev/null || true; root="$HOME/.mozilla/firefox"; mkdir -p "$root"; tmp=$(mktemp); [[ -f "$root/profiles.ini" ]] && awk -F= '/^Path=/{print $2}' "$root/profiles.ini" | while read -r p; do [[ "$p" = /* ]] && echo "$p" || echo "$root/$p"; done > "$tmp"; find "$root" -maxdepth 2 -type f -name cert9.db -printf '%h\n' 2>/dev/null >> "$tmp"; sort -u "$tmp" | while read -r p; do register_profile "$p"; done; rm -f "$tmp"; }
check_card(){ log "=== Läser in/kontrollerar kortläsare ==="; [[ "$CHECK_CARD_READER" == 1 ]] || return; [[ "$DRY_RUN" == 1 ]] && return; sudo systemctl restart pcscd; sleep 2; command -v pcsc_scan >/dev/null && { log "Kör pcsc_scan i max 8 sekunder. Timeout är förväntat."; timeout 8 pcsc_scan 2>&1 | tee -a "$LOG_FILE" || true; }; }

preflight(){ cat <<INFO

============================================================
Preflight
============================================================
Detta script installerar FK Extern-komponenter för Ubuntu.
Endast för anställda/konsulter på Försäkringskassan.
Ingen support ges på scriptet.
Firefox måste redan vara .deb.
Media: ${MEDIA_DIR:-automatisk}
Logg: $LOG_FILE
============================================================

INFO
}
confirm(){ [[ "$ASSUME_YES" == 1 || "$DRY_RUN" == 1 ]] && return; read -r -p "Fortsätta? [y/N] " a; [[ "$a" =~ ^([yY]|yes|YES|ja|Ja)$ ]] || fail "Avbrutet av användaren."; }
summary(){ cat <<DONE

============================================================
FK Extern-installation klar
============================================================

Net iD: $NETID_LIB

Citrix standardkonfiguration har lämnats orörd om du inte använde explicit felsökningsflagga.

Viktigt:
  Starta om datorn efter installationen innan du testar Citrix/remote desktop.
  Utan omstart kan smartkortet rapporteras som tomt eller PIN-flödet utebli.

Logg: $LOG_FILE
============================================================

DONE
[[ "$DRY_RUN" != 1 ]] && touch /tmp/fkextern-reboot-required 2>/dev/null || true; }

main(){ parse_args "$@"; log "Startar $SCRIPT_NAME"; require_cmd sudo; require_cmd dpkg; require_cmd apt-get; require_cmd grep; require_cmd readlink; require_cmd awk; require_cmd find; sudo -v; preflight; confirm; check_ubuntu; check_firefox_deb; ensure_media; log "Använder media-katalog: $MEDIA_DIR"; [[ "$RESET_BEFORE_INSTALL" == 1 ]] && reset_install || log "Hoppar över rensning."; reset_user_cache; install_pcsc; verify_pcsclite; install_citrix; install_netid; configure_citrix_optional; register_firefox; check_card; summary; ok "Klart."; }
main "$@"
