#!/usr/bin/env bash
set -uo pipefail

LOG_FILE="/tmp/fkextern-diagnose.log"
NETID_TIMEOUT_SECONDS="${NETID_TIMEOUT_SECONDS:-5}"
PCSC_SCAN_TIMEOUT_SECONDS="${PCSC_SCAN_TIMEOUT_SECONDS:-8}"
MODUTIL_TIMEOUT_SECONDS="${MODUTIL_TIMEOUT_SECONDS:-5}"
FOUND_ACTION=0

log(){ echo "$*" | tee -a "$LOG_FILE"; }
section(){ log ""; log "=== $* ==="; }
sanitize_home(){ sed "s#${HOME}#~#g"; }
add_action(){ FOUND_ACTION=1; log "[ACTION] $*"; }
run_timeout(){ command -v timeout >/dev/null 2>&1 && timeout "$@" || shift; "$@"; }
run_cmd(){ local sec="$1"; shift; set +e; timeout "$sec" "$@" 2>&1 | sanitize_home | tee -a "$LOG_FILE"; rc=${PIPESTATUS[0]}; set -e; [[ $rc -eq 124 ]] && log "[WARN] Kommando timeout efter ${sec}s: $*"; [[ $rc -ne 0 && $rc -ne 124 ]] && log "[WARN] Kommando returnerade $rc: $*"; }

: > "$LOG_FILE"
section "FK Extern diagnose"
log "Logg: $LOG_FILE"
log "Tid: $(date '+%Y-%m-%d %H:%M:%S')"

section "OS"; [[ -f /etc/os-release ]] && cat /etc/os-release | sanitize_home | tee -a "$LOG_FILE" || uname -a | sanitize_home | tee -a "$LOG_FILE"
section "Firefox binary"; { which -a firefox || true; command -v firefox >/dev/null 2>&1 && readlink -f "$(command -v firefox)" || true; firefox --version 2>/dev/null || true; } | sanitize_home | tee -a "$LOG_FILE"
section "Firefox processer"; ps -ef | grep -i '[f]irefox' | sanitize_home | tee -a "$LOG_FILE" || true
section "APT Firefox"; { dpkg -l | grep -Ei '^ii\s+firefox|firefox-l10n' || true; apt-cache policy firefox 2>/dev/null | sed -n '1,30p' || true; } | sanitize_home | tee -a "$LOG_FILE"
section "Snap Firefox"; command -v snap >/dev/null 2>&1 && snap list firefox 2>/dev/null | sanitize_home | tee -a "$LOG_FILE" || log "snap saknas eller firefox snap saknas"
section "Flatpak Firefox"; command -v flatpak >/dev/null 2>&1 && flatpak list 2>/dev/null | grep -i firefox | sanitize_home | tee -a "$LOG_FILE" || log "flatpak saknas eller firefox flatpak saknas"
section "pcscd"; run_cmd 5 systemctl status pcscd --no-pager

section "libpcsclite för Citrix"
dpkg -s libpcsclite1 >/dev/null 2>&1 && log "[OK] libpcsclite1 är installerat" || { log "[WARN] libpcsclite1 saknas"; add_action "Installera libpcsclite1"; }
dpkg -s libpcsclite-dev >/dev/null 2>&1 && log "[OK] libpcsclite-dev är installerat" || { log "[WARN] libpcsclite-dev saknas"; add_action "Installera libpcsclite-dev: sudo apt install libpcsclite-dev"; }
if command -v ldconfig >/dev/null 2>&1; then ldconfig -p | grep -q 'libpcsclite\.so ' && { log "[OK] libpcsclite.so finns i linker-cache"; ldconfig -p | grep 'libpcsclite\.so' | tee -a "$LOG_FILE" || true; } || { log "[WARN] libpcsclite.so saknas i linker-cache"; add_action "Installera libpcsclite-dev och kör sudo ldconfig"; }; fi

section "Kortläsare"; command -v pcsc_scan >/dev/null 2>&1 && { log "Kör pcsc_scan i max ${PCSC_SCAN_TIMEOUT_SECONDS}s. Timeout är normalt."; run_cmd "$PCSC_SCAN_TIMEOUT_SECONDS" pcsc_scan; } || add_action "Installera pcsc-tools"
section "NetiD"; { ls -l /lib/netid/libnetid.so /usr/lib/netid/libnetid.so /usr/bin/netid 2>/dev/null || true; } | sanitize_home | tee -a "$LOG_FILE"; [[ -x /usr/bin/netid ]] && { log "Kör /usr/bin/netid -command i max ${NETID_TIMEOUT_SECONDS}s..."; run_cmd "$NETID_TIMEOUT_SECONDS" /usr/bin/netid -command; } || add_action "Net iD verkar saknas. Kör installationen igen."
section "NetiD-processer"; ps -ef | grep -Ei '[n]etid|[p]ointsharp' | sanitize_home | tee -a "$LOG_FILE" || true

section "Citrix paket"; dpkg -l | grep -Ei 'icaclient|ctxusb|libpcsclite|pcsc|netid|libnss3-tools' | sanitize_home | tee -a "$LOG_FILE" || true
section "Citrix processer"; ps -ef | grep -Ei 'ctxwebhelper|ctxusb|ctxusbd|wfica|adapter|AuthManager|ServiceRecord|selfservice|icasessionmgr' | grep -v grep | sanitize_home | tee -a "$LOG_FILE" || true
ps -ef | grep -E '[i]casessionmgr.*<defunct>' >/dev/null 2>&1 && add_action "Defunct icasessionmgr hittades. Rensa Citrix-processer eller starta om datorn."
section "Citrix tjänster"; { systemctl status ctxusbd --no-pager 2>/dev/null || true; systemctl status ctxcwalogd --no-pager 2>/dev/null || true; } | sanitize_home | tee -a "$LOG_FILE"
section "Citrix SmartCard config"; { grep -n -A8 -B2 '\[SmartCard\]' /opt/Citrix/ICAClient/config/module.ini 2>/dev/null || true; grep -n -A3 -B3 'PKCS11module' /opt/Citrix/ICAClient/config/AuthManConfig.xml 2>/dev/null || true; grep -n -A3 -B3 'DefaultPKCS11Lib' /opt/Citrix/ICAClient/config/scardConfig.json 2>/dev/null || true; } | sanitize_home | tee -a "$LOG_FILE"
section "Citrix USB config"; { grep -n 'class=0b' /opt/Citrix/ICAClient/usb.conf 2>/dev/null || true; head -80 /opt/Citrix/ICAClient/usb.conf 2>/dev/null || true; } | sanitize_home | tee -a "$LOG_FILE"

section "Citrix kända fel och signaler"
CITRIX_LOG="/var/log/citrix/ICAClient.log"
SESSION_READY=0; READER_INSERTED=0; NO_PIN=0; PCSCLITE_ERROR=0; SEGFAULT=0; VDA_CERT_CACHE=0
if [[ -f "$CITRIX_LOG" ]]; then
  sudo grep -iE 'libpcsclite\.so|Failed to cache VDA certificate|No PIN acquired|Session launch readiness achieved|Inserting new Reader|Segmentation fault|segfault|OpenGL rendering enabled|Succeed in launch session|doDecryptData failed|SSLGetDataFn failed|Peer closed the socket|certificate|cert|permission|denied|fatal|error' "$CITRIX_LOG" | tail -160 | sanitize_home | tee -a "$LOG_FILE" || true
  sudo grep -qi 'Session launch readiness achieved' "$CITRIX_LOG" && SESSION_READY=1
  sudo grep -qi 'Inserting new Reader' "$CITRIX_LOG" && READER_INSERTED=1
  sudo grep -qi 'No PIN acquired' "$CITRIX_LOG" && NO_PIN=1
  sudo grep -qi 'libpcsclite\.so: cannot open shared object file' "$CITRIX_LOG" && PCSCLITE_ERROR=1
  sudo grep -qiE 'segmentation fault|segfault' "$CITRIX_LOG" && SEGFAULT=1
  sudo grep -qi 'Failed to cache VDA certificate' "$CITRIX_LOG" && VDA_CERT_CACHE=1
  [[ $PCSCLITE_ERROR -eq 1 ]] && add_action "Citrix-loggen innehåller libpcsclite.so-fel. Installera libpcsclite-dev."
  [[ $SEGFAULT -eq 1 ]] && add_action "Citrix-loggen innehåller segfault. Rensa processer och jämför Citrix-konfig."
  [[ $NO_PIN -eq 1 ]] && add_action "No PIN acquired hittades. Om installationen nyss körts: starta om datorn."
  [[ $VDA_CERT_CACHE -eq 1 ]] && log "[INFO] Failed to cache VDA certificate hittades. Inte nödvändigtvis blockerande om sessionen blir visuellt redo."
  [[ $SESSION_READY -eq 1 ]] && log "[OK] Citrix-loggen visar att sessionen blivit visuellt redo."
  [[ $READER_INSERTED -eq 1 ]] && log "[OK] Citrix-loggen visar att smartkortsläsare skickats in i sessionen."
else
  log "$CITRIX_LOG saknas"
fi

section "ICA launch file"; [[ -f "$HOME/.ICAClient/launch.ica" ]] && { log "~/.ICAClient/launch.ica finns"; sed -n '1,120p' "$HOME/.ICAClient/launch.ica" | sanitize_home | tee -a "$LOG_FILE"; } || log "~/.ICAClient/launch.ica saknas"
section "Firefox-profiler och Net iD NSS-modul"
if command -v modutil >/dev/null 2>&1; then
  found=0
  while IFS= read -r db; do found=1; profile=$(dirname "$db"); log "--- ${profile//$HOME/~}"; timeout "$MODUTIL_TIMEOUT_SECONDS" modutil -dbdir "sql:$profile" -list 2>/dev/null | grep -A50 'Net iD' | sanitize_home | tee -a "$LOG_FILE" || true; done < <(find "$HOME/.mozilla/firefox" -maxdepth 2 -name cert9.db 2>/dev/null)
  [[ $found -eq 1 ]] || log "Ingen Firefox-profil med cert9.db hittades under ~/.mozilla/firefox"
else
  add_action "Installera libnss3-tools: sudo apt install libnss3-tools"
fi

section "Tolkning"
if ! command -v firefox >/dev/null 2>&1; then add_action "Firefox saknas. Installera Firefox .deb först."; else real=$(readlink -f "$(command -v firefox)" 2>/dev/null || true); [[ "$real" == /snap/* || "$real" == /app/* ]] && add_action "Firefox verkar vara sandboxad. Installera riktig .deb-version."; fi
[[ -f /tmp/fkextern-reboot-required ]] && add_action "Installationsscriptet har markerat att omstart krävs. Starta om datorn innan första riktiga Citrix-testet."
[[ $SESSION_READY -eq 1 && $READER_INSERTED -eq 1 && $NO_PIN -eq 0 ]] && log "[OK] Citrix-session och smartkortsläsare ser ut att fungera i loggen."
[[ $SESSION_READY -eq 1 && $READER_INSERTED -eq 1 && $NO_PIN -eq 1 ]] && add_action "Sessionen startar och läsaren syns, men PIN hämtades inte. Starta om om detta är direkt efter installation."
[[ $FOUND_ACTION -eq 0 ]] && log "[OK] Inga uppenbara lokala blockerande fel hittades av diagnosen."
section "Sammanfattning"; log "Diagnostik klar."; log "Logg: $LOG_FILE"; log "Jag ger ingen support på scriptet."
