#!/usr/bin/env bash
# =============================================================================
# reidentify.sh - Network Identity Randomizer
# Interactive CLI shell for MAC, hostname, TTL, and IP management.
# All changes are runtime-only and revert on reboot.
# Usage: ./reidentify.sh
# =============================================================================

set -uo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
BLU='\033[0;34m'
MAG='\033[0;35m'
CYN='\033[0;36m'
WHT='\033[1;37m'
DIM='\033[2m'
RST='\033[0m'

# ─── Global state ─────────────────────────────────────────────────────────────
IFACE=""
ORIG_MAC=""
ORIG_HOSTNAME=""
ORIG_TTL4=""
ORIG_TTL6=""
NEW_MAC=""
NEW_HOSTNAME=""
NEW_TTL4=""
NEW_TTL6=""
HOSTS_PATCHED=false
HOSTS_APPENDED=false
SESSION_LOG=()

# ─── Helpers ──────────────────────────────────────────────────────────────────
info()    { echo -e "  ${BLU}[*]${RST} $*"; }
ok()      { echo -e "  ${GRN}[✓]${RST} $*"; SESSION_LOG+=("$(echo -e "[OK] $*" | sed 's/\x1b\[[0-9;]*m//g')"); }
warn()    { echo -e "  ${YLW}[!]${RST} $*"; }
err()     { echo -e "  ${RED}[✗]${RST} $*"; SESSION_LOG+=("$(echo -e "[ERR] $*" | sed 's/\x1b\[[0-9;]*m//g')"); }
section() {
  echo ""
  echo -e "${CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
  echo -e "${CYN}  ▶ $*${RST}"
  echo -e "${CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
}

# ─── Banner ───────────────────────────────────────────────────────────────────
banner() {
  clear
  echo -e "${CYN}"
  echo "  ██████  ███████ ██ ██████  ███████ ███    ██ ████████ ██ ███████ ██    ██"
  echo "  ██   ██ ██      ██ ██   ██ ██      ████   ██    ██    ██ ██       ██  ██ "
  echo "  ██████  █████   ██ ██   ██ █████   ██ ██  ██    ██    ██ █████     ████  "
  echo "  ██   ██ ██      ██ ██   ██ ██      ██  ██ ██    ██    ██ ██         ██   "
  echo "  ██   ██ ███████ ██ ██████  ███████ ██   ████    ██    ██ ██         ██   "
  echo -e "${RST}${DIM}           Network Identity Randomizer  •  runtime changes only${RST}"
  echo ""
}

# ─── Sudo self-escalation ─────────────────────────────────────────────────────
check_root() {
  sudo -k
  if [[ $EUID -ne 0 ]]; then
    echo -e "\n  ${CYN}[*]${RST} Root privileges required. Enter your sudo password:\n"
    exec sudo bash "$0" "$@"
    exit $?
  fi
  echo -e "\n  ${CYN}[*]${RST} Confirm your sudo password to proceed:\n"
  if ! sudo -v; then
    echo -e "  ${RED}[✗]${RST} Authentication failed. Exiting."
    exit 1
  fi
}

# ─── Dependency check ─────────────────────────────────────────────────────────
check_deps() {
  local missing=()
  for cmd in ip sysctl hostname; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "  ${RED}[✗]${RST} Missing required utilities: ${missing[*]}"
    exit 1
  fi
}


# ─── OUI vendor prefixes ──────────────────────────────────────────────────────
declare -A OUI_MAP=(
  [apple]="ac:de:48"
  [iphone]="f4:f1:5a"
  [samsung]="54:bd:79"
  [google]="f4:f1:5a"
  [dell]="f8:db:88"
  [lenovo]="10:02:b5"
  [intel]="00:1b:21"
  [raspberry]="dc:a6:32"
  [nintendo]="98:b6:e9"
  [random]=""
)

# ─── Command help strings ─────────────────────────────────────────────────────
declare -A CMD_HELP=(
  [iface]="$(cat <<'EOF'
  Usage:    iface [name]
  
  Sets the active network interface for all subsequent commands.
  If no name is given, lists available interfaces and prompts for one.
  
  Captures the original MAC, hostname, and TTL at this point so
  they can be restored later with revert.
  
  Examples:
    iface            - list interfaces and prompt
    iface eth0       - set eth0 as active interface
    iface wlan0      - set wlan0 as active interface
EOF
)"
  [mac]="$(cat <<'EOF'
  Usage:    mac [vendor]

  Randomizes the MAC address on the active interface.
  Optionally accepts a vendor name to spoof a specific manufacturer OUI.
  If no vendor is given, prompts with a numbered menu.

  The change is runtime-only and does not survive a reboot.

  Examples:
    mac              - prompt for vendor
    mac random       - fully random MAC
    mac apple        - Apple OUI prefix + random suffix
    mac dell         - Dell OUI prefix + random suffix

    The vendor options are:
    apple
    iphone
    samsung
    google
    dell
    lenovo
    intel
    raspberry
    random
EOF
)"
  [hostname]="$(cat <<'EOF'
  Usage:    hostname

  Randomizes the system hostname to a random Device-XXXXXX name.
  Uses hostnamectl on systemd systems, falls back to legacy hostname command.
  Also updates /etc/hosts to keep name resolution working.

  Reverts cleanly with the revert command.
EOF
)"
  [ttl]="$(cat <<'EOF'
  Usage:    ttl [value]

  Sets the IPv4 TTL and IPv6 Hop Limit to the given value.
  If no value is given, shows common presets and prompts.

  Common values:
    64   - Linux / Android default
    128  - Windows default
    255  - Maximum / router-like

  Examples:
    ttl          - prompt with presets
    ttl 64       - set TTL to 64
    ttl 128      - spoof Windows-like TTL    
EOF
)"
  [ip]="$(cat <<'EOF'
  Usage:    ip

  Renews the DHCP lease on the active interface to request a new IP.
  Automatically detects and uses NetworkManager, systemd-networkd,
  dhclient, or dhcpcd depending on what is running.
EOF
)"
  [dhcp]="$(cat <<'EOF'
    Usage:  dhcp [profile]
    
    Spoofs DHCP fingerprint to a different OS

    Profile options:
    Windows 10
    MacOS
    Linux
    Android
    IOS
    Random
EOF
)"
  [run]="$(cat <<'EOF'
  Usage:    run

  Runs all randomization steps in sequence:
    1. mac
    2. hostname
    3. ttl  (prompts for value)
    4. ip
    5. status

  Interface must be set first with iface.
EOF
)"
  [status]="$(cat <<'EOF'
  Usage:    status

  Displays the current state of the active interface:
    - Interface name
    - Current MAC address
    - Current IP address
    - Current hostname
    - IPv4 TTL and IPv6 Hop Limit

  Also shows original values captured at iface set time.
EOF
)"
  [revert]="$(cat <<'EOF'
  Usage:    revert

  Restores all changes made this session:
    - Hostname restored via hostnamectl
    - /etc/hosts restored from backup
    - IPv4 TTL and IPv6 Hop Limit restored
    - MAC address restored on active interface

  Has no effect if no changes have been made.
EOF
)"
  [log]="$(cat <<'EOF'
  Usage:    log

  Displays a numbered list of all actions taken this session,
  including both successful operations and errors.
EOF
)"
  [clear]="$(cat <<'EOF'
  Usage:    clear

  Clears the screen and redraws the banner.
EOF
)"
  [help]="$(cat <<'EOF'
  Usage:    help [command]

  With no argument, lists all available commands.
  With a command name, shows detailed help for that command.

  Examples:
    help         - show all commands
    help mac     - show mac command details
    help revert  - show revert command details
EOF
)"
)

# ─── Status bar ───────────────────────────────────────────────────────────────
#print_status_bar() {
 # local iface_display="${IFACE:-${DIM}none${RST}}"
 # local mac_display="${NEW_MAC:-${DIM}unchanged${RST}}"
 # local host_display="${NEW_HOSTNAME:-${DIM}unchanged${RST}}"
 # local ttl_display="${NEW_TTL4:-${DIM}unchanged${RST}}"
 # local ip_display
 # ip_display=$(ip -4 addr show "${IFACE:-lo}" 2>/dev/null | awk '/inet /{print $2}' | head -1)
 # ip_display="${ip_display:-${DIM}none${RST}}"

 # echo ""
 # echo -e "${WHT}┌─────────────────────────────────────────────────────────────┐${RST}"
 # printf  "${WHT}│${RST}  %-12s ${CYN}%-20s${RST}  %-8s ${CYN}%-16s${RST} ${WHT}│${RST}\n" \
 #   "Interface:" "$iface_display" "IP:" "$ip_display"
 # printf  "${WHT}│${RST}  %-12s ${GRN}%-20s${RST}  %-8s ${GRN}%-16s${RST} ${WHT}│${RST}\n" \
 #   "MAC:" "$mac_display" "TTL:" "$ttl_display"
 # printf  "${WHT}│${RST}  %-12s ${YLW}%-46s${RST} ${WHT}│${RST}\n" \
 #   "Hostname:" "$host_display"
 # echo -e "${WHT}└─────────────────────────────────────────────────────────────┘${RST}"
 # echo ""
#}

# ─── Help menu ────────────────────────────────────────────────────────────────
print_help() {
  local topic="${1:-}"

  if [[ -n "$topic" ]]; then
    if [[ -n "${CMD_HELP[$topic]+_}" ]]; then
      echo ""
      echo -e "${CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
      echo -e "${CYN}  ▶ help: ${topic}${RST}"
      echo -e "${CYN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
      echo -e "${CMD_HELP[$topic]}"
    else
      err "No help found for '${topic}'. Type ${WHT}help${RST} for a list of commands."
    fi
    return
  fi

  echo ""
  echo -e "${WHT}  Available commands:${RST}"
  echo ""
  echo -e "  ${CYN}iface${RST}       [name]    Set or change the active network interface"
  echo -e "  ${CYN}mac${RST}         [vendor]  Randomize MAC address (optional vendor preset)"
  echo -e "  ${CYN}hostname${RST}              Randomize system hostname"
  echo -e "  ${CYN}ttl${RST}         [value]   Set IPv4/IPv6 TTL (prompts if no value given)"
  echo -e "  ${CYN}ip${RST}                    Renew DHCP lease / request new IP address"
  echo -e "  ${CYN}dhcp${RST}        [profile] Spoof DHCP fingerprint (windows10, macos, linux, ios…)"
  echo -e "  ${CYN}run${RST}                   Run all steps at once (mac + hostname + ttl + ip)"
  echo -e "  ${CYN}status${RST}                Show current interface, MAC, hostname, TTL, IP"
  echo -e "  ${CYN}revert${RST}                Revert all changes made this session"
  echo -e "  ${CYN}log${RST}                   Show session activity log"
  echo -e "  ${CYN}clear${RST}                 Clear the screen"
  echo -e "  ${CYN}help${RST}        [command] Show this menu or detailed help for a command"
  echo -e "  ${CYN}exit${RST}                  Exit the program"
  echo ""
  echo -e "  ${DIM}Tip: type help <command> for detailed usage${RST}"
  echo ""
}

# ─── cmd: iface ───────────────────────────────────────────────────────────────
cmd_iface() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    echo ""
    echo -e "  ${WHT}Available interfaces:${RST}"
    ip -o link show | awk -F': ' '{print "    " $2}' | grep -v '^\s*lo'
    echo ""
    read -rp "  Enter interface name: " target
  fi
  if ! ip link show "$target" &>/dev/null; then
    err "Interface '$target' not found."
    return
  fi
  IFACE="$target"
  ORIG_MAC=$(ip link show "$IFACE" | awk '/ether/{print $2}')
  ORIG_HOSTNAME=$(hostname)
  ORIG_TTL4=$(sysctl -n net.ipv4.ip_default_ttl)
  ORIG_TTL6=$(sysctl -n net.ipv6.conf.all.hop_limit 2>/dev/null || echo "N/A")
  ok "Active interface set to ${WHT}$IFACE${RST}  (MAC: ${DIM}$ORIG_MAC${RST})"
}

# ─── cmd: mac ─────────────────────────────────────────────────────────────────
cmd_mac() {
  if [[ -z "$IFACE" ]]; then
    err "No interface set. Run: iface <name>"
    return
  fi
  section "MAC Address Randomization"

  local vendor="${1:-}"

  # If no vendor passed, prompt with a menu
  if [[ -z "$vendor" ]]; then
    echo ""
    echo -e "  ${WHT}Vendor presets:${RST}"
    local i=1
    local keys=()
    for key in "${!OUI_MAP[@]}"; do
      printf "  ${CYN}%2d)${RST} %s\n" "$i" "$key"
      keys+=("$key")
      (( i++ ))
    done
    echo ""
    read -rp "  Choose vendor (number or name) [random]: " choice
    choice="${choice:-random}"

    # Accept number or name
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      vendor="${keys[$((choice-1))]:-random}"
    else
      vendor="$choice"
    fi
  fi

  # Validate
  if [[ -z "${OUI_MAP[$vendor]+_}" ]]; then
    warn "Unknown vendor '${vendor}', falling back to random."
    vendor="random"
  fi

  # Build the MAC
  local oui="${OUI_MAP[$vendor]}"
  local suffix
  suffix=$(hexdump -vn3 -e '1/1 "%02x:"' /dev/urandom | sed 's/:$//')

  local new_mac
  if [[ -z "$oui" ]]; then
    # fully random - apply LAA/unicast bits to first byte
    local full
    full=$(hexdump -vn6 -e '1/1 "%02x:"' /dev/urandom | sed 's/:$//')
    local first_byte
    first_byte=$(printf '%02x' $(( (0x${full:0:2} | 0x02) & 0xFE )))
    new_mac="${first_byte}${full:2}"
  else
    # vendor prefix + random suffix - OUI first byte is already correct
    new_mac="${oui}:${suffix}"
  fi

  info "Vendor:        ${YLW}${vendor}${RST}"
  info "Generated MAC: ${YLW}${new_mac}${RST}"
  info "Taking $IFACE down..."
  ip link set "$IFACE" down
  ip link set "$IFACE" address "$new_mac"
  info "Bringing $IFACE back up..."
  ip link set "$IFACE" up
  sleep 1

  local verified
  verified=$(ip link show "$IFACE" | awk '/ether/{print $2}')
  NEW_MAC="$verified"
  if [[ "$verified" == "$new_mac" ]]; then
    ok "MAC changed: ${DIM}${ORIG_MAC}${RST} → ${GRN}${verified}${RST}  ${DIM}(${vendor})${RST}"
  else
    warn "Driver reported: $verified (requested $new_mac)"
  fi
}

# ─── cmd: hostname ────────────────────────────────────────────────────────────
cmd_hostname() {
  section "Hostname Randomization"

  [[ -z "$ORIG_HOSTNAME" ]] && ORIG_HOSTNAME=$(hostname)

  local rand_suffix
  rand_suffix=$(tr -dc '0-9' </dev/urandom | head -c 6)
  local new_host="Device-${rand_suffix}"

  info "Setting hostname to: ${YLW}${new_host}${RST}"

  if command -v hostnamectl &>/dev/null; then
    hostnamectl set-hostname "$new_host"
  else
    hostname "$new_host"
    echo "$new_host" > /etc/hostname
  fi

  NEW_HOSTNAME="$new_host"

  if grep -q "^127\.0\.1\.1" /etc/hosts; then
    sed -i.reidentify_bak "s/^127\.0\.1\.1.*/127.0.1.1\t${new_host}/" /etc/hosts
    HOSTS_PATCHED=true
  else
    echo -e "127.0.1.1\t${new_host}" >> /etc/hosts
    HOSTS_APPENDED=true
  fi

  ok "Hostname changed: ${DIM}${ORIG_HOSTNAME}${RST} → ${GRN}${new_host}${RST}"
}
# ─── cmd: ttl ─────────────────────────────────────────────────────────────────
cmd_ttl() {
  section "TTL / Hop Limit"
  local value="${1:-}"

  [[ -z "$ORIG_TTL4" ]] && ORIG_TTL4=$(sysctl -n net.ipv4.ip_default_ttl)
  [[ -z "$ORIG_TTL6" ]] && ORIG_TTL6=$(sysctl -n net.ipv6.conf.all.hop_limit 2>/dev/null || echo "N/A")

  if [[ -z "$value" ]]; then
    echo ""
    echo -e "  ${WHT}Common presets:${RST}"
    echo -e "  ${DIM}  64  - Linux / Android default${RST}"
    echo -e "  ${DIM}  128 - Windows default${RST}"
    echo -e "  ${DIM}  255 - Maximum / router-like${RST}"
    echo ""
    while true; do
      read -rp "  Enter TTL (1-255) or Enter for default [64]: " value
      value="${value:-64}"
      if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 1 && value <= 255 )); then
        break
      fi
      warn "Invalid - enter a number between 1 and 255."
    done
  else
    if ! [[ "$value" =~ ^[0-9]+$ ]] || (( value < 1 || value > 255 )); then
      err "Invalid TTL '$value' - must be 1-255."
      return
    fi
  fi

  info "Setting IPv4 TTL to ${YLW}${value}${RST}..."
  sysctl -w net.ipv4.ip_default_ttl="$value"
  NEW_TTL4=$(sysctl -n net.ipv4.ip_default_ttl)
  ok "IPv4 TTL → ${GRN}${NEW_TTL4}${RST}"

  if sysctl net.ipv6.conf.all.hop_limit &>/dev/null; then
    info "Setting IPv6 Hop Limit to ${YLW}${value}${RST}..."
    sysctl -w net.ipv6.conf.all.hop_limit="$value"
    NEW_TTL6=$(sysctl -n net.ipv6.conf.all.hop_limit)
    ok "IPv6 Hop Limit → ${GRN}${NEW_TTL6}${RST}"
  else
    warn "IPv6 sysctl not available - skipping."
    NEW_TTL6="N/A"
  fi
}

# ─── cmd: ip (renew) ──────────────────────────────────────────────────────────
cmd_ip() {
  if [[ -z "$IFACE" ]]; then
    err "No interface set. Run: iface <name>"
    return
  fi
  section "IP Renewal"

  if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    info "NetworkManager - reconnecting $IFACE..."
    nmcli device disconnect "$IFACE" &>/dev/null || true
    sleep 1
    nmcli device connect "$IFACE" &>/dev/null || true
    ok "NetworkManager reconnected $IFACE."
  elif systemctl is-active --quiet systemd-networkd 2>/dev/null; then
    info "systemd-networkd - restarting..."
    systemctl restart systemd-networkd
    ok "systemd-networkd restarted."
  elif command -v dhclient &>/dev/null; then
    info "dhclient - releasing lease..."
    dhclient -r "$IFACE" &>/dev/null || true
    sleep 1
    info "Requesting new lease..."
    dhclient "$IFACE" &>/dev/null || true
    ok "dhclient renewed lease."
  elif command -v dhcpcd &>/dev/null; then
    info "dhcpcd - renewing lease..."
    dhcpcd -n "$IFACE" &>/dev/null || true
    ok "dhcpcd renewed."
  else
    warn "No network manager found. Try manually:"
    warn "  dhclient $IFACE  OR  nmcli device connect $IFACE"
    return
  fi

  sleep 2
  local new_ip
  new_ip=$(ip -4 addr show "$IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -1)
  ok "New IP: ${GRN}${new_ip:-"(pending)"}${RST}"
}

# ─── cmd: dhcp spoof ──────────────────────────────────────────────────────────
cmd_dhcp_spoof() {
  section "DHCP Fingerprint Spoofing"

  local profile="${1:-}"

  # Profiles based on real OS DHCP fingerprints
  declare -A DHCP_PROFILES=(
    [windows10]="1 3 6 15 31 33 43 44 46 47 119 121 249 252"
    [macos]="1 121 3 6 15 119 252 95 44 46"
    [linux]="1 28 2 3 15 6 119 12 44 47 26 121 42"
    [android]="1 33 3 6 28 51 58 59"
    [ios]="1 121 3 6 15 119 252 95 44 46 47"
    [random]=""
  )

  if [[ -z "$profile" ]]; then
    echo ""
    echo -e "  ${WHT}DHCP fingerprint presets:${RST}"
    local i=1
    for key in "${!DHCP_PROFILES[@]}"; do
      printf "  ${CYN}%2d)${RST} %s\n" "$i" "$key"
      (( i++ ))
    done
    echo ""
    read -rp "  Choose profile [linux]: " profile
    profile="${profile:-linux}"
  fi

  if [[ -z "${DHCP_PROFILES[$profile]+_}" ]]; then
    warn "Unknown profile '${profile}', falling back to linux."
    profile="linux"
  fi

  local options="${DHCP_PROFILES[$profile]}"

  # Build a temporary dhclient config
  local conf="/tmp/reidentify_dhclient.conf"

  # Random client identifier to avoid leaking hostname/MAC in DHCP
  local rand_id
  rand_id=$(hexdump -vn8 -e '1/1 "%02x"' /dev/urandom)

  cat > "$conf" <<EOF
send dhcp-client-identifier "${rand_id}";
request ${options// /, };
EOF

  info "Profile:   ${YLW}${profile}${RST}"
  info "Options:   ${DIM}${options}${RST}"
  info "Client ID: ${DIM}${rand_id}${RST}"
  info "Config written to: ${DIM}${conf}${RST}"

  if command -v dhclient &>/dev/null; then
    info "Releasing current lease..."
    dhclient -r "$IFACE" &>/dev/null || true
    sleep 1
    info "Requesting new lease with spoofed fingerprint..."
    timeout 10 dhclient -cf "$conf" "$IFACE" &>/dev/null || warn "DHCP renewal timed out."
    local new_ip
    new_ip=$(ip -4 addr show "$IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    ok "New IP: ${GRN}${new_ip:-"(pending)"}${RST}"
  else
    warn "dhclient not found — config written but not applied."
    warn "Run manually: dhclient -cf ${conf} ${IFACE}"
  fi
}

# ─── cmd: run all ─────────────────────────────────────────────────────────────
cmd_run() {
  if [[ -z "$IFACE" ]]; then
    err "No interface set. Run: iface <name>"
    return
  fi
  cmd_mac
  cmd_hostname
  cmd_ttl "${1:-}"
  cmd_ip
  cmd_dhcp_spoof
  cmd_status
}

# ─── cmd: status ──────────────────────────────────────────────────────────────
cmd_status() {
  section "Current Status"
  local cur_mac cur_host cur_ip cur_ttl4 cur_ttl6

  if [[ -n "$IFACE" ]]; then
    cur_mac=$(ip link show "$IFACE" 2>/dev/null | awk '/ether/{print $2}')
    cur_ip=$(ip -4 addr show "$IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -1)
  else
    cur_mac="${DIM}N/A${RST}"
    cur_ip="${DIM}N/A${RST}"
  fi
  cur_host=$(hostname)
  cur_ttl4=$(sysctl -n net.ipv4.ip_default_ttl)
  cur_ttl6=$(sysctl -n net.ipv6.conf.all.hop_limit 2>/dev/null || echo "N/A")

  printf "  %-18s ${WHT}%s${RST}\n"  "Interface:"   "${IFACE:-none}"
  printf "  %-18s ${CYN}%s${RST}\n"  "MAC address:" "${cur_mac:-N/A}"
  printf "  %-18s ${CYN}%s${RST}\n"  "IP address:"  "${cur_ip:-none}"
  printf "  %-18s ${YLW}%s${RST}\n"  "Hostname:"    "$cur_host"
  printf "  %-18s ${GRN}%s${RST}\n"  "IPv4 TTL:"    "$cur_ttl4"
  printf "  %-18s ${GRN}%s${RST}\n"  "IPv6 Hop:"    "$cur_ttl6"

  if [[ -n "$ORIG_MAC" ]]; then
    echo ""
    echo -e "  ${DIM}Original MAC:      $ORIG_MAC${RST}"
    echo -e "  ${DIM}Original hostname: $ORIG_HOSTNAME${RST}"
    echo -e "  ${DIM}Original TTL4:     $ORIG_TTL4${RST}"
  fi
}

# ─── cmd: revert ──────────────────────────────────────────────────────────────
cmd_revert() {
  section "Reverting Changes"
  local reverted=0

  if [[ -n "$ORIG_HOSTNAME" && "$(hostname)" != "$ORIG_HOSTNAME" ]]; then
    hostname "$ORIG_HOSTNAME"
    ok "Hostname restored: ${GRN}${ORIG_HOSTNAME}${RST}"
    NEW_HOSTNAME=""
    reverted=1
  fi

  if [[ "$HOSTS_PATCHED" == "true" && -f /etc/hosts.reidentify_bak ]]; then
    cp /etc/hosts.reidentify_bak /etc/hosts
    ok "Restored /etc/hosts from backup."
    HOSTS_PATCHED=false
  fi

  if [[ -n "$ORIG_TTL4" ]]; then
    sysctl -qw net.ipv4.ip_default_ttl="$ORIG_TTL4"
    ok "IPv4 TTL restored: ${GRN}${ORIG_TTL4}${RST}"
    NEW_TTL4=""
    reverted=1
  fi

  if [[ -n "$ORIG_TTL6" && "$ORIG_TTL6" != "N/A" ]]; then
    sysctl -qw net.ipv6.conf.all.hop_limit="$ORIG_TTL6"
    ok "IPv6 Hop Limit restored: ${GRN}${ORIG_TTL6}${RST}"
    NEW_TTL6=""
    reverted=1
  fi

  if [[ $reverted -eq 0 ]]; then
    info "Nothing to revert - no changes have been made this session."
  else
    warn "MAC address changes require a reboot or manual restore to revert."
    warn "  Original MAC was: ${ORIG_MAC:-unknown}"
  fi

if [[ -n "$ORIG_MAC" && -n "$IFACE" ]]; then
  ip link set "$IFACE" down
  ip link set "$IFACE" address "$ORIG_MAC"
  ip link set "$IFACE" up
  local verified
  verified=$(ip link show "$IFACE" | awk '/ether/{print $2}')
  if [[ "$verified" == "$ORIG_MAC" ]]; then
    ok "MAC restored: ${GRN}${ORIG_MAC}${RST}"
  else
    warn "MAC restore may have failed. Driver reported: $verified"
    warn "Original was: ${ORIG_MAC}"
  fi
  NEW_MAC=""
  reverted=1
fi
}

# ─── cmd: log ─────────────────────────────────────────────────────────────────
cmd_log() {
  section "Session Log"
  if [[ ${#SESSION_LOG[@]} -eq 0 ]]; then
    info "No activity recorded yet."
    return
  fi
  local i=1
  for entry in "${SESSION_LOG[@]}"; do
    printf "  ${DIM}%3d.${RST}  %s\n" "$i" "$entry"
    (( i++ ))
  done
}

# ─── Interrupt handler ────────────────────────────────────────────────────────
handle_interrupt() {
  echo ""
  warn "Caught interrupt. Type ${WHT}exit${RST} to quit, or ${WHT}revert${RST} to undo changes."
}
trap handle_interrupt INT

# ─── Main REPL loop ───────────────────────────────────────────────────────────
repl() {
  print_help
  #print_status_bar

  while true; do
    echo -ne "${CYN}reidentify${RST}${DIM}>${RST} "
    read -r raw_input || { echo ""; break; }

    # Split input into command + args
    read -ra parts <<< "$raw_input"
    local cmd="${parts[0]:-}"
    local args=("${parts[@]:1}")

    case "$cmd" in
      iface)    cmd_iface    "${args[@]:-}" ;;
      mac)      cmd_mac "${args[0]:-}" ;;
      hostname) cmd_hostname ;;
      ttl)      cmd_ttl      "${args[0]:-}" ;;
      ip)       cmd_ip ;;
      dhcp)     cmd_dhcp_spoof "${args[0]:-}" ;;
      run)      cmd_run      "${args[0]:-}" ;;
      status)   cmd_status ;;
      revert)   cmd_revert ;;
      log)      cmd_log ;;
      clear)    banner; print_status_bar ;;
      help)     print_help "${args[0]:-}" ;;
      exit|quit) break ;;
      "")       ;; # ignore blank lines
      *)
        err "Unknown command: '${cmd}'. Type ${WHT}help${RST} for a list of commands."
        ;;
    esac
    echo ""
  done

  echo ""
  echo -e "  ${DIM}All runtime changes will revert on next reboot.${RST}"
  echo -e "  ${DIM}Run ${WHT}revert${DIM} before exiting to undo changes now.${RST}"
  echo ""
  echo -e "  ${CYN}Goodbye.${RST}"
  echo ""
}

# ─── Entry point ──────────────────────────────────────────────────────────────
main() {
  banner
  check_root "$@"
  check_deps
  repl
}

main "$@"
