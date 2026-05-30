#!/usr/bin/env bash
set -uo pipefail

LOG_FILE="/tmp/fkextern-diagnose.log"

NETID_TIMEOUT_SECONDS="${NETID_TIMEOUT_SECONDS:-5}"
PCSC_SCAN_TIMEOUT_SECONDS="${PCSC_SCAN_TIMEOUT_SECONDS:-8}"
MODUTIL_TIMEOUT_SECONDS="${MODUTIL_TIMEOUT_SECONDS:-5}"

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

run_timeout() {
  local seconds="$1"
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

run_section_command() {
  local seconds="$1"
  shift

  set +e
  run_timeout "$seconds" "$@" 2>&1 | sanitize_home | tee -a "$LOG_FILE"
  local rc="${PIPESTATUS[0]}"
  set -e

  if [[ "$rc" -eq 124 ]]; then
    log "[WARN] Kommando timeout efter ${seconds}s: $*"
  elif [[ "$rc" -ne 0 ]]; then
    log "[WARN] Kommando returnerade $rc: $*"
  fi
}

: > "$LOG_FILE"

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
ps -ef | grep -i '[f]irefox' | sanitize_home | tee -a "$LOG_FILE" || true

section "APT Firefox"
{
  dpkg -l | grep -Ei '^ii\s+firefox|firefox-l10n' || true
  apt-cache policy firefox 2>/dev/null | sed -n '1,30p' || true
} | sanitize_home | tee -a "$LOG_FILE"

section "Snap Firefox"
if command -v snap >/dev/null 2>&1; then
  snap list firefox 2>/dev/null | sanitize_home | tee -a "$LOG_FILE" || true
else
  log "snap saknas"
fi

section "Flatpak Firefox"
if command -v flatpak >/dev/null 2>&1; then
  flatpak list 2>/dev/null | grep -i firefox | sanitize_home | tee -a "$LOG_FILE" || true
else
  log "flatpak saknas"
fi

section "pcscd"
run_section_command 5 systemctl status pcscd --no-pager

section "Kortläsare"
if command -v pcsc_scan >/dev/null 2>&1; then
  log "Kör pcsc_scan i max ${PCSC_SCAN_TIMEOUT_SECONDS}s..."
  run_section_command "$PCSC_SCAN_TIMEOUT_SECONDS" pcsc_scan
else
  log "pcsc_scan saknas"
fi

section "NetiD"
{
  ls -l /lib/netid/libnetid.so /usr/lib/netid/libnetid.so /usr/bin/netid 2>/dev/null || true
} | sanitize_home | tee -a "$LOG_FILE"

if [[ -x /usr/bin/netid ]]; then
  log "Kör /usr/bin/netid -command i max ${NETID_TIMEOUT_SECONDS}s..."
  run_section_command "$NETID_TIMEOUT_SECONDS" /usr/bin/netid -command
else
  log "/usr/bin/netid saknas eller är inte körbar"
fi

section "NetiD-processer"
ps -ef | grep -Ei '[n]etid|[p]ointsharp' | sanitize_home | tee -a "$LOG_FILE" || true

section "Citrix paket"
{
  dpkg -l | grep -Ei 'icaclient|ctxusb|libpcsclite|pcsc|netid|libnss3-tools' || true
} | sanitize_home | tee -a "$LOG_FILE"

section "Citrix filer"
{
  ls -la /opt/Citrix/ICAClient 2>/dev/null | head -80 || true
} | sanitize_home | tee -a "$LOG_FILE"

section "Citrix processer"
ps -ef | grep -Ei 'ctxusb|ctxusbd|wfica|AuthManager|ServiceRecord|selfservice' | grep -v grep | sanitize_home | tee -a "$LOG_FILE" || true

section "Citrix tjänster"
{
  systemctl status ctxusbd --no-pager 2>/dev/null || true
  systemctl list-units --type=service | grep -Ei 'ctx|citrix|usb' || true
  systemctl list-unit-files | grep -Ei 'ctx|citrix|usb' || true
} | sanitize_home | tee -a "$LOG_FILE"

section "Citrix SmartCard config"
{
  grep -n -A8 -B2 '\[SmartCard\]' /opt/Citrix/ICAClient/config/module.ini 2>/dev/null || true
  grep -n -A3 -B3 'PKCS11module' /opt/Citrix/ICAClient/config/AuthManConfig.xml 2>/dev/null || true
  grep -n -A3 -B3 'DefaultPKCS11Lib' /opt/Citrix/ICAClient/config/scardConfig.json 2>/dev/null || true
} | sanitize_home | tee -a "$LOG_FILE"

section "Citrix USB config"
{
  head -60 /opt/Citrix/ICAClient/usb.conf 2>/dev/null || true
} | sanitize_home | tee -a "$LOG_FILE"

section "Firefox-profiler och Net iD NSS-modul"
if command -v modutil >/dev/null 2>&1; then
  found_profile=0

  while IFS= read -r db; do
    found_profile=1
    profile="$(dirname "$db")"
    log "--- ${profile//$HOME/~}"

    set +e
    run_timeout "$MODUTIL_TIMEOUT_SECONDS" modutil -dbdir "sql:$profile" -list 2>/dev/null \
      | grep -A50 "Net iD" \
      | sanitize_home \
      | tee -a "$LOG_FILE"
    rc="${PIPESTATUS[0]}"
    set -e

    if [[ "$rc" -eq 124 ]]; then
      log "[WARN] modutil timeout efter ${MODUTIL_TIMEOUT_SECONDS}s för ${profile//$HOME/~}"
    fi
  done < <(find "$HOME/.mozilla/firefox" -maxdepth 2 -name cert9.db 2>/dev/null)

  if [[ "${found_profile:-0}" -eq 0 ]]; then
    log "Ingen Firefox-profil med cert9.db hittades under ~/.mozilla/firefox"
  fi
else
  log "modutil saknas"
fi

section "Sammanfattning"
log "Diagnostik klar."
log "Om scriptet tidigare fastnade vid NetiD var sannolik orsak att '/usr/bin/netid -command' blockerade."
log "Den här versionen kör NetiD, pcsc_scan och modutil med timeout."
log "Logg: $LOG_FILE"
log "Jag ger ingen support på scriptet."
