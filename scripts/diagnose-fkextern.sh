#!/usr/bin/env bash
set -uo pipefail

LOG_FILE="/tmp/fkextern-diagnose.log"

NETID_TIMEOUT_SECONDS="${NETID_TIMEOUT_SECONDS:-5}"
PCSC_SCAN_TIMEOUT_SECONDS="${PCSC_SCAN_TIMEOUT_SECONDS:-8}"
MODUTIL_TIMEOUT_SECONDS="${MODUTIL_TIMEOUT_SECONDS:-5}"

FOUND_ACTION=0

log() {
  echo "$*" | tee -a "$LOG_FILE"
}

section() {
  log ""
  log "=== $* ==="
}

sanitize_home() {
  sed "s#${HOME}#~#g"
}

add_action() {
  FOUND_ACTION=1
  log "[ACTION] $*"
}

run_timeout() {
  local seconds="$1"
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

run_cmd() {
  local seconds="$1"
  local rc

  shift

  set +e
  run_timeout "$seconds" "$@" 2>&1 | sanitize_home | tee -a "$LOG_FILE"
  rc=${PIPESTATUS[0]}
  set -e

  if [[ "$rc" -eq 124 ]]; then
    log "[WARN] Kommando timeout efter ${seconds}s: $*"
  elif [[ "$rc" -ne 0 ]]; then
    log "[WARN] Kommando returnerade $rc: $*"
  fi
}

log_processes_matching() {
  local pattern="$1"

  # shellcheck disable=SC2009
  ps -ef | grep -Ei "$pattern" | grep -v grep | sanitize_home | tee -a "$LOG_FILE" || true
}

check_package_installed() {
  local package="$1"
  local action_text="$2"

  if dpkg -s "$package" >/dev/null 2>&1; then
    log "[OK] $package är installerat"
  else
    log "[WARN] $package saknas"
    add_action "$action_text"
  fi
}

: >"$LOG_FILE"

SESSION_READY=0
READER_INSERTED=0
NO_PIN=0
PCSCLITE_ERROR=0
SEGFAULT=0
VDA_CERT_CACHE=0
OPENGL_ENABLED=0

section "FK Extern diagnose"
log "Logg: $LOG_FILE"
log "Tid: $(date '+%Y-%m-%d %H:%M:%S')"

section "OS"
if [[ -f /etc/os-release ]]; then
  cat /etc/os-release | sanitize_home | tee -a "$LOG_FILE"
else
  uname -a | sanitize_home | tee -a "$LOG_FILE"
fi

section "Firefox binary"
{
  which -a firefox || true

  if command -v firefox >/dev/null 2>&1; then
    readlink -f "$(command -v firefox)" || true
    firefox --version 2>/dev/null || true
  fi
} | sanitize_home | tee -a "$LOG_FILE"

section "Firefox processer"
log_processes_matching '[f]irefox'

section "APT Firefox"
{
  dpkg -l | grep -Ei '^ii\s+firefox|firefox-l10n' || true
  apt-cache policy firefox 2>/dev/null | sed -n '1,30p' || true
} | sanitize_home | tee -a "$LOG_FILE"

section "Snap Firefox"
if command -v snap >/dev/null 2>&1; then
  if ! snap list firefox 2>/dev/null | sanitize_home | tee -a "$LOG_FILE"; then
    log "firefox snap saknas"
  fi
else
  log "snap saknas"
fi

section "Flatpak Firefox"
if command -v flatpak >/dev/null 2>&1; then
  if ! flatpak list 2>/dev/null | grep -i firefox | sanitize_home | tee -a "$LOG_FILE"; then
    log "firefox flatpak saknas"
  fi
else
  log "flatpak saknas"
fi

section "pcscd"
run_cmd 5 systemctl status pcscd --no-pager

section "libpcsclite för Citrix"
check_package_installed "libpcsclite1" "Installera libpcsclite1: sudo apt install libpcsclite1"
check_package_installed "libpcsclite-dev" "Installera libpcsclite-dev: sudo apt install libpcsclite-dev"

if command -v ldconfig >/dev/null 2>&1; then
  if ldconfig -p | grep -q 'libpcsclite\.so '; then
    log "[OK] libpcsclite.so finns i linker-cache"
    ldconfig -p | grep 'libpcsclite\.so' | tee -a "$LOG_FILE" || true
  elif [[ -e /usr/lib/x86_64-linux-gnu/libpcsclite.so ]]; then
    log "[OK] libpcsclite.so finns på /usr/lib/x86_64-linux-gnu/libpcsclite.so"
  else
    log "[WARN] libpcsclite.so saknas"
    add_action "Installera libpcsclite-dev och kör sudo ldconfig"
  fi
else
  log "[WARN] ldconfig saknas"
fi

section "Kortläsare"
if command -v pcsc_scan >/dev/null 2>&1; then
  log "Kör pcsc_scan i max ${PCSC_SCAN_TIMEOUT_SECONDS}s. Timeout är normalt."
  run_cmd "$PCSC_SCAN_TIMEOUT_SECONDS" pcsc_scan
else
  add_action "Installera pcsc-tools: sudo apt install pcsc-tools"
fi

section "NetiD"
{
  ls -l /lib/netid/libnetid.so /usr/lib/netid/libnetid.so /usr/bin/netid 2>/dev/null || true
} | sanitize_home | tee -a "$LOG_FILE"

if [[ -x /usr/bin/netid ]]; then
  log "Kör /usr/bin/netid -command i max ${NETID_TIMEOUT_SECONDS}s..."
  run_cmd "$NETID_TIMEOUT_SECONDS" /usr/bin/netid -command
else
  add_action "Net iD verkar saknas. Kör installationen igen."
fi

section "NetiD-processer"
log_processes_matching '[n]etid|[p]ointsharp'

section "Ljudkällor"
if command -v wpctl >/dev/null 2>&1; then
  wpctl status | sed -n '/Sources:/,/Sinks:/p' | sanitize_home | tee -a "$LOG_FILE" || true
else
  log "wpctl saknas"
fi

if command -v pactl >/dev/null 2>&1; then
  pactl list sources short | sanitize_home | tee -a "$LOG_FILE" || true
else
  log "pactl saknas"
fi

section "Citrix paket"
dpkg -l | grep -Ei 'icaclient|ctxusb|libpcsclite|pcsc|netid|libnss3-tools' | sanitize_home | tee -a "$LOG_FILE" || true

section "Citrix processer"
log_processes_matching 'ctxwebhelper|ctxusb|ctxusbd|wfica|adapter|AuthManager|ServiceRecord|selfservice|icasessionmgr'

# shellcheck disable=SC2009
if ps -ef | grep -E '[i]casessionmgr.*<defunct>' >/dev/null 2>&1; then
  add_action "Defunct icasessionmgr hittades. Rensa Citrix-processer eller starta om datorn."
fi

section "Citrix tjänster"
{
  systemctl status ctxusbd --no-pager 2>/dev/null || true
  systemctl status ctxcwalogd --no-pager 2>/dev/null || true
} | sanitize_home | tee -a "$LOG_FILE"

section "Citrix SmartCard config"
{
  grep -n -A8 -B2 '\[SmartCard\]' /opt/Citrix/ICAClient/config/module.ini 2>/dev/null || true
  grep -n -A3 -B3 'PKCS11module' /opt/Citrix/ICAClient/config/AuthManConfig.xml 2>/dev/null || true
  grep -n -A3 -B3 'DefaultPKCS11Lib' /opt/Citrix/ICAClient/config/scardConfig.json 2>/dev/null || true
} | sanitize_home | tee -a "$LOG_FILE"

section "Citrix USB config"
{
  grep -n 'class=0b' /opt/Citrix/ICAClient/usb.conf 2>/dev/null || true
  head -80 /opt/Citrix/ICAClient/usb.conf 2>/dev/null || true
} | sanitize_home | tee -a "$LOG_FILE"

section "Citrix kända fel och signaler"
CITRIX_LOG="/var/log/citrix/ICAClient.log"

if [[ -f "$CITRIX_LOG" ]]; then
  sudo grep -iE 'libpcsclite\.so|Failed to cache VDA certificate|No PIN acquired|Session launch readiness achieved|Inserting new Reader|Segmentation fault|segfault|OpenGL rendering enabled|Succeed in launch session|AudioIn|Blue|Snowball|Default recording|doDecryptData failed|SSLGetDataFn failed|Peer closed the socket|certificate|cert|permission|denied|fatal|error' "$CITRIX_LOG" \
    | tail -180 \
    | sanitize_home \
    | tee -a "$LOG_FILE" || true

  if sudo grep -qi 'Session launch readiness achieved' "$CITRIX_LOG"; then
    SESSION_READY=1
  fi

  if sudo grep -qi 'Inserting new Reader' "$CITRIX_LOG"; then
    READER_INSERTED=1
  fi

  if sudo grep -qi 'No PIN acquired' "$CITRIX_LOG"; then
    NO_PIN=1
  fi

  if sudo grep -qi 'libpcsclite\.so: cannot open shared object file' "$CITRIX_LOG"; then
    PCSCLITE_ERROR=1
  fi

  if sudo grep -qiE 'segmentation fault|segfault' "$CITRIX_LOG"; then
    SEGFAULT=1
  fi

  if sudo grep -qi 'Failed to cache VDA certificate' "$CITRIX_LOG"; then
    VDA_CERT_CACHE=1
  fi

  if sudo grep -qi 'OpenGL rendering enabled' "$CITRIX_LOG"; then
    OPENGL_ENABLED=1
  fi

  if [[ "$PCSCLITE_ERROR" == "1" ]]; then
    add_action "Citrix-loggen innehåller libpcsclite.so-fel. Installera libpcsclite-dev."
  fi

  if [[ "$SEGFAULT" == "1" ]]; then
    add_action "Citrix-loggen innehåller segfault. Rensa processer och jämför Citrix-konfig."
  fi

  if [[ "$NO_PIN" == "1" ]]; then
    add_action "No PIN acquired hittades. Om installationen nyss körts: starta om datorn."
  fi

  if [[ "$VDA_CERT_CACHE" == "1" ]]; then
    log "[INFO] Failed to cache VDA certificate hittades. Inte nödvändigtvis blockerande om sessionen blir visuellt redo."
  fi

  if [[ "$OPENGL_ENABLED" == "1" ]]; then
    log "[INFO] OpenGL rendering enabled hittades."
  fi

  if [[ "$SESSION_READY" == "1" ]]; then
    log "[OK] Citrix-loggen visar att sessionen blivit visuellt redo."
  fi

  if [[ "$READER_INSERTED" == "1" ]]; then
    log "[OK] Citrix-loggen visar att smartkortsläsare skickats in i sessionen."
  fi
else
  log "$CITRIX_LOG saknas"
fi

section "ICA launch file"
if [[ -f "$HOME/.ICAClient/launch.ica" ]]; then
  log "$HOME/.ICAClient/launch.ica finns"
  sed -n '1,120p' "$HOME/.ICAClient/launch.ica" | sanitize_home | tee -a "$LOG_FILE"
else
  log "$HOME/.ICAClient/launch.ica saknas"
fi

section "Firefox-profiler och Net iD NSS-modul"
if command -v modutil >/dev/null 2>&1; then
  found_profile=0

  while IFS= read -r cert_db; do
    profile_directory="$(dirname "$cert_db")"
    found_profile=1

    log "--- ${profile_directory//$HOME/~}"

    run_timeout "$MODUTIL_TIMEOUT_SECONDS" modutil -dbdir "sql:$profile_directory" -list 2>/dev/null \
      | grep -A50 'Net iD' \
      | sanitize_home \
      | tee -a "$LOG_FILE" || true
  done < <(find "$HOME/.mozilla/firefox" -maxdepth 2 -name cert9.db 2>/dev/null)

  if [[ "$found_profile" != "1" ]]; then
    log "Ingen Firefox-profil med cert9.db hittades under $HOME/.mozilla/firefox"
  fi
else
  add_action "Installera libnss3-tools: sudo apt install libnss3-tools"
fi

section "Tolkning"

if ! command -v firefox >/dev/null 2>&1; then
  add_action "Firefox saknas. Installera Firefox .deb först."
else
  firefox_realpath="$(readlink -f "$(command -v firefox)" 2>/dev/null || true)"

  if [[ "$firefox_realpath" == /snap/* || "$firefox_realpath" == /app/* ]]; then
    add_action "Firefox verkar vara sandboxad. Installera riktig .deb-version."
  fi
fi

if [[ -f /tmp/fkextern-reboot-required ]]; then
  add_action "Installationsscriptet har markerat att omstart krävs. Starta om datorn innan första riktiga Citrix-testet."
fi

if [[ "$SESSION_READY" == "1" && "$READER_INSERTED" == "1" && "$NO_PIN" == "0" ]]; then
  log "[OK] Citrix-session och smartkortsläsare ser ut att fungera i loggen."
fi

if [[ "$SESSION_READY" == "1" && "$READER_INSERTED" == "1" && "$NO_PIN" == "1" ]]; then
  add_action "Sessionen startar och läsaren syns, men PIN hämtades inte. Starta om om detta är direkt efter installation."
fi

if [[ "$FOUND_ACTION" == "0" ]]; then
  log "[OK] Inga uppenbara lokala blockerande fel hittades av diagnosen."
fi

section "Sammanfattning"
log "Diagnostik klar."
log "Logg: $LOG_FILE"
log "Jag ger ingen support på scriptet."
