#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/tmp/fkextern-diagnose.log"

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
  command -v firefox >/dev/null 2>&1 && readlink -f "$(command -v firefox)" || true
  firefox --version 2>/dev/null || true
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
systemctl status pcscd --no-pager 2>&1 | sanitize_home | tee -a "$LOG_FILE" || true

section "Kortläsare"
if command -v pcsc_scan >/dev/null 2>&1; then
  timeout 8 pcsc_scan 2>&1 | sanitize_home | tee -a "$LOG_FILE" || true
else
  log "pcsc_scan saknas"
fi

section "NetiD"
{
  ls -l /lib/netid/libnetid.so /usr/lib/netid/libnetid.so /usr/bin/netid 2>/dev/null || true
  /usr/bin/netid -command 2>/dev/null || true
} | sanitize_home | tee -a "$LOG_FILE"

section "Citrix"
{
  dpkg -l | grep -Ei 'icaclient|ctxusb' || true
  ls -la /opt/Citrix/ICAClient 2>/dev/null | head -50 || true
} | sanitize_home | tee -a "$LOG_FILE"

section "Firefox-profiler och Net iD NSS-modul"
if command -v modutil >/dev/null 2>&1; then
  find "$HOME/.mozilla/firefox" -maxdepth 2 -name cert9.db 2>/dev/null | while read -r db; do
    profile="$(dirname "$db")"
    log "--- ${profile//$HOME/~}"
    modutil -dbdir "sql:$profile" -list 2>/dev/null | grep -A50 "Net iD" | sanitize_home | tee -a "$LOG_FILE" || true
  done
else
  log "modutil saknas"
fi

section "Sammanfattning"
log "Skicka inte loggen brett om den innehåller miljöinformation du inte vill dela."
log "Jag ger ingen support på scriptet."
