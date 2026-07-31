#!/usr/bin/env bash

readonly INSTALLER_VERSION="2.0.0"
readonly MANAGED_BEGIN="# RPI_KIOSK_MANAGED_BEGIN"
readonly MANAGED_END="# RPI_KIOSK_MANAGED_END"
readonly LEGACY_BEGIN="#KIOSKPARANCS_BEGIN"
readonly LEGACY_END="#KIOSKPARANCS_END"
readonly KIOSK_ETC_DIR="/etc/rpi-kiosk"
readonly KIOSK_STATE_DIR="/var/lib/rpi-kiosk"
readonly KIOSK_SHARE_DIR="/usr/local/share/rpi-kiosk"
readonly KIOSK_BIN_DIR="/usr/local/bin"

CURRENT_USER=""
HOME_DIR=""
BOOT_CONFIG=""
BOOT_CMDLINE=""
RUN_TMP=""
RUN_LOG=""
ACTIVE_PID=""

ASK_APT_UPDATE="y"
ASK_APT_UPGRADE="n"
ENABLE_WAYLAND="y"
ENABLE_CHROMIUM="y"
ENABLE_GREETD="n"
ENABLE_BROWSER="y"
ENABLE_INCOGNITO="n"
ENABLE_NET_WAIT="n"
PING_HOST="1.1.1.1"
NETWORK_WAIT_SECONDS="30"
WORK_URL="http://192.168.1.40:18006"
ENABLE_IDLE="y"
IDLE_URL="https://kiosk.athq.cc"
IDLE_TIMEOUT="20"
ENABLE_CURSOR_HIDE="y"
ENABLE_WALLPAPER="y"
ENABLE_SPLASH="y"
FORCE_RESOLUTION="y"
DISPLAY_OUTPUT="HDMI-A-1"
DISPLAY_MODE="1920x1080@60"
ENABLE_ROTATION="n"
DISPLAY_TRANSFORM="normal"
ENABLE_HDMI_AUDIO="y"
ENABLE_CEC="n"
ENABLE_NETWATCH="y"
NETWATCH_REBOOT_MINUTES="20"

color() {
  local code="$1"
  shift
  if [[ -t 1 ]]; then
    printf '\033[%sm%s\033[0m' "$code" "$*"
  else
    printf '%s' "$*"
  fi
}

info() { printf '%s %s\n' "$(color 36 '•')" "$*"; }
success() { printf '%s %s\n' "$(color 32 '✔')" "$*"; }
warn() { printf '%s %s\n' "$(color 33 '!')" "$*" >&2; }
error() { printf '%s %s\n' "$(color 31 '✖')" "$*" >&2; }
die() { error "$*"; exit 1; }
section() { printf '\n%s\n' "$(color '1;34' "== $* ==")"; }

banner() {
  printf '\n%s\n' "$(color '1;35' 'Raspberry Pi KIOSK – Alu-Technika Kft.')"
  printf '%s\n' "Professzionális telepítő v${INSTALLER_VERSION}"
}

cleanup_runtime() {
  if [[ -t 1 ]]; then
    tput cnorm 2>/dev/null || true
  fi
  if [[ -n "${RUN_TMP:-}" && -d "$RUN_TMP" ]]; then
    rm -rf -- "$RUN_TMP"
  fi
}

handle_signal() {
  warn "A telepítés megszakítva."
  if [[ "${ACTIVE_PID:-}" =~ ^[1-9][0-9]*$ ]] && kill -0 "$ACTIVE_PID" 2>/dev/null; then
    kill "$ACTIVE_PID" 2>/dev/null || true
    wait "$ACTIVE_PID" 2>/dev/null || true
  fi
  exit 130
}

init_runtime() {
  RUN_TMP="$(mktemp -d)"
  RUN_LOG="$RUN_TMP/last-step.log"
  trap cleanup_runtime EXIT
  trap handle_signal INT TERM

  if [[ "$(id -u)" -eq 0 ]]; then
    die "A telepítőt normál felhasználóként futtasd; a szükséges műveletekhez sudo-t használ."
  fi

  CURRENT_USER="$(id -un)"
  HOME_DIR="$(getent passwd "$CURRENT_USER" | cut -d: -f6)"
  [[ -n "$HOME_DIR" && -d "$HOME_DIR" ]] || die "Nem határozható meg a felhasználó home könyvtára."

  if [[ -f /boot/firmware/config.txt ]]; then
    BOOT_CONFIG="/boot/firmware/config.txt"
    BOOT_CMDLINE="/boot/firmware/cmdline.txt"
  else
    BOOT_CONFIG="/boot/config.txt"
    BOOT_CMDLINE="/boot/cmdline.txt"
  fi
}

preflight() {
  section "Rendszerellenőrzés"
  local command_name
  for command_name in sudo apt-get systemctl install awk sed grep flock getent; do
    command -v "$command_name" >/dev/null 2>&1 || die "Hiányzó alapvető parancs: $command_name"
  done

  local os_id="" os_version="" os_name=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    os_id="${ID:-}"
    os_version="${VERSION_ID:-}"
    os_name="${PRETTY_NAME:-ismeretlen Linux}"
  fi

  info "Operációs rendszer: $os_name"
  if [[ "$os_id" != "debian" && "$os_id" != "raspbian" ]]; then
    warn "A telepítő Debian/Raspberry Pi OS rendszerre készült."
  elif [[ "$os_version" != "13" ]]; then
    warn "A támogatott célverzió Debian 13/Trixie; észlelt verzió: ${os_version:-ismeretlen}."
  else
    success "Debian 13/Trixie kompatibilis rendszer."
  fi

  local model="ismeretlen"
  if [[ -r /proc/device-tree/model ]]; then
    model="$(tr -d '\0' </proc/device-tree/model)"
  fi
  info "Hardver: $model"
  if [[ "$model" != *"Raspberry Pi 4"* ]]; then
    warn "A telepítő Raspberry Pi 4-re van optimalizálva."
  fi

  [[ -f "$BOOT_CONFIG" ]] || warn "Boot konfiguráció nem található: $BOOT_CONFIG"
  [[ -f "$BOOT_CMDLINE" ]] || warn "Kernel parancssor nem található: $BOOT_CMDLINE"
}

acquire_sudo() {
  section "Adminisztrátori jogosultság"
  sudo -v || die "A sudo jogosultság megszerzése sikertelen."
  success "sudo jogosultság rendben."
}

is_yes() { [[ "$1" == "y" ]]; }

ask_yes_no() {
  local prompt="$1"
  local default="$2"
  local hint input
  [[ "$default" == "y" ]] && hint="I/n" || hint="i/N"
  while true; do
    read -r -p "$prompt [$hint]: " input
    input="${input:-$default}"
    case "${input,,}" in
      y|yes|i|igen) printf 'y\n'; return 0 ;;
      n|no|nem) printf 'n\n'; return 0 ;;
      *) warn "Kérlek igennel (i) vagy nemmel (n) válaszolj." ;;
    esac
  done
}

ask_value() {
  local prompt="$1"
  local default="$2"
  local value
  read -r -p "$prompt [alapértelmezett: $default]: " value
  printf '%s\n' "${value:-$default}"
}

ask_positive_integer() {
  local prompt="$1"
  local default="$2"
  local value
  while true; do
    read -r -p "$prompt [alapértelmezett: $default]: " value
    value="${value:-$default}"
    if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
      printf '%s\n' "$value"
      return 0
    fi
    warn "Nullánál nagyobb egész szám szükséges."
  done
}

ask_choice() {
  local prompt="$1"
  shift
  local choices=("$@")
  local selection
  printf '%s\n' "$prompt:" >&2
  select selection in "${choices[@]}"; do
    if [[ -n "$selection" ]]; then
      printf '%s\n' "$selection"
      return 0
    fi
    warn "Érvénytelen választás."
  done
}

print_choice() {
  local label="$1"
  local value="$2"
  if is_yes "$value"; then
    success "$label: igen"
  else
    info "$label: nem"
  fi
}

validate_http_url() {
  [[ "$1" =~ ^https?://[^[:space:]]+$ ]]
}

url_host() {
  local value="${1#*://}"
  value="${value%%/*}"
  value="${value%%:*}"
  printf '%s\n' "$value"
}

validate_host() {
  [[ "$1" =~ ^[A-Za-z0-9._:-]+$ ]]
}

validate_display_name() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

validate_display_mode() {
  [[ "$1" =~ ^[0-9]+x[0-9]+(@[0-9]+([.][0-9]+)?)?$ ]]
}

detect_display_output() {
  local connector
  for connector in /sys/class/drm/card*-HDMI-A-*; do
    [[ -r "$connector/status" ]] || continue
    if [[ "$(<"$connector/status")" == "connected" ]]; then
      basename "$connector" | sed -E 's/^card[0-9]+-//'
      return 0
    fi
  done
  printf 'HDMI-A-1\n'
}

spinner() {
  local pid="$1"
  local label="$2"
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local index=0
  if [[ -t 1 ]]; then
    tput civis 2>/dev/null || true
  fi
  while kill -0 "$pid" 2>/dev/null; do
    if [[ -t 1 ]]; then
      printf '\r%s %s' "$(color 35 "${frames[$index]}")" "$label"
      index=$(((index + 1) % ${#frames[@]}))
    fi
    sleep 0.1
  done
  [[ -t 1 ]] && printf '\r\033[K'
  if [[ -t 1 ]]; then
    tput cnorm 2>/dev/null || true
  fi
}

run_step() {
  local label="$1"
  shift
  : >"$RUN_LOG"
  "$@" >"$RUN_LOG" 2>&1 &
  local pid=$!
  ACTIVE_PID="$pid"
  spinner "$pid" "$label"
  if wait "$pid"; then
    ACTIVE_PID=""
    success "$label"
    return 0
  else
    local status=$?
    ACTIVE_PID=""
    error "$label sikertelen (hibakód: $status)."
    if [[ -s "$RUN_LOG" ]]; then
      tail -n 40 "$RUN_LOG" >&2
    fi
    cp "$RUN_LOG" "$HOME_DIR/rpi-kiosk-install-error.log" 2>/dev/null || true
    error "A részletes hibanapló megmaradt: $HOME_DIR/rpi-kiosk-install-error.log"
    return "$status"
  fi
}

run_optional_step() {
  local label="$1"
  shift
  if ! run_step "$label" "$@"; then
    warn "$label kihagyva; a telepítés folytatódik."
    return 0
  fi
}

prepare_managed_directories() {
  sudo install -d -m 0755 "$KIOSK_ETC_DIR" "$KIOSK_STATE_DIR" "$KIOSK_SHARE_DIR"
}

write_root_content() {
  local target="$1"
  local mode="$2"
  local content="$3"
  local tmp="$RUN_TMP/root-content"
  printf '%s' "$content" >"$tmp"
  sudo install -D -m "$mode" "$tmp" "$target"
}

install_root_file() {
  local source="$1"
  local target="$2"
  local mode="$3"
  sudo install -D -m "$mode" "$source" "$target"
}

remove_root_file() {
  local target="$1"
  sudo rm -f -- "$target"
}

strip_managed_blocks() {
  local source="$1"
  local target="$2"
  awk \
    -v begin="$MANAGED_BEGIN" \
    -v end="$MANAGED_END" \
    -v legacy_begin="$LEGACY_BEGIN" \
    -v legacy_end="$LEGACY_END" '
      $0 == begin || $0 == legacy_begin { skipping=1; next }
      $0 == end || $0 == legacy_end { skipping=0; next }
      !skipping { print }
    ' "$source" >"$target"
}

update_managed_block() {
  local target="$1"
  local content="$2"
  local use_sudo="${3:-n}"
  local mode="${4:-0644}"
  local current="$RUN_TMP/managed-current"
  local cleaned="$RUN_TMP/managed-cleaned"
  local output="$RUN_TMP/managed-output"

  if [[ -f "$target" ]]; then
    if is_yes "$use_sudo"; then
      sudo cat "$target" >"$current"
    else
      cat "$target" >"$current"
    fi
  else
    : >"$current"
  fi

  strip_managed_blocks "$current" "$cleaned"
  awk 'NF { last=NR } { lines[NR]=$0 } END { for (i=1; i<=last; i++) print lines[i] }' "$cleaned" >"$output"

  if [[ -n "$content" ]]; then
    [[ -s "$output" ]] && printf '\n' >>"$output"
    printf '%s\n' "$MANAGED_BEGIN" >>"$output"
    printf '%s\n' "$content" >>"$output"
    printf '%s\n' "$MANAGED_END" >>"$output"
  fi

  if is_yes "$use_sudo"; then
    sudo install -D -m "$mode" "$output" "$target"
  else
    install -D -m "$mode" "$output" "$target"
  fi
}

shell_quote() {
  printf '%q' "$1"
}

write_state_flag() {
  local name="$1"
  sudo touch "$KIOSK_STATE_DIR/$name"
}

has_state_flag() {
  sudo test -f "$KIOSK_STATE_DIR/$1"
}

remove_state_flag() {
  sudo rm -f -- "$KIOSK_STATE_DIR/$1"
}

verify_file() {
  local path="$1"
  [[ -s "$path" ]] || die "Az ellenőrzés során hiányzó vagy üres fájl: $path"
}

verify_root_file() {
  local path="$1"
  sudo test -s "$path" || die "Az ellenőrzés során hiányzó vagy üres fájl: $path"
}

verify_installation() {
  section "Telepítés ellenőrzése"
  local autostart="$HOME_DIR/.config/labwc/autostart"
  local managed_count legacy_count
  managed_count="$(grep -Fc "$MANAGED_BEGIN" "$autostart" 2>/dev/null || true)"
  legacy_count="$(grep -Fc "$LEGACY_BEGIN" "$autostart" 2>/dev/null || true)"
  [[ -x "$autostart" ]] || die "A labwc autostart fájl nem végrehajtható."
  [[ "$managed_count" == "1" ]] ||
    die "A labwc autostart kezelt blokkjainak száma nem egy: $managed_count"
  [[ "$legacy_count" == "0" ]] ||
    die "Régi KIOSKPARANCS blokk maradt a labwc autostart fájlban."
  if grep -Eqi 'swayidle.*wlopm[[:space:]]+--off' "$autostart"; then
    die "A Raspberry Pi OS kijelző-kikapcsoló swayidle sora még aktív."
  fi

  if is_yes "$ENABLE_BROWSER"; then
    verify_root_file "$KIOSK_BIN_DIR/rpi-kiosk-browser"
    verify_root_file "$KIOSK_ETC_DIR/browser.env"
    bash -n "$KIOSK_BIN_DIR/rpi-kiosk-browser" ||
      die "A telepített böngészővezérlő szintaktikailag hibás."
  fi

  if is_yes "$ENABLE_WALLPAPER"; then
    verify_root_file "$KIOSK_SHARE_DIR/wallpaper.png"
  fi

  if is_yes "$ENABLE_CURSOR_HIDE"; then
    if ! python3 - "$HOME_DIR/.config/labwc/rc.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
ET.parse(sys.argv[1])
PY
    then
      die "A labwc rc.xml XML-ellenőrzése sikertelen."
    fi
  fi

  if is_yes "$ENABLE_SPLASH"; then
    verify_root_file "/usr/share/plymouth/themes/rpi-kiosk/rpi-kiosk.plymouth"
    [[ "$(sudo plymouth-set-default-theme 2>/dev/null)" == "rpi-kiosk" ]] ||
      die "Nem az rpi-kiosk az aktív Plymouth-téma."
  fi

  if [[ -f "$BOOT_CMDLINE" ]]; then
    local line_count video_count splash_count consoleblank_count
    line_count="$(sudo awk 'END { print NR }' "$BOOT_CMDLINE")"
    [[ "$line_count" == "1" ]] || die "A cmdline.txt nem pontosan egysoros."
    video_count="$(sudo cat "$BOOT_CMDLINE" | tr ' ' '\n' | grep -c '^video=' || true)"
    splash_count="$(sudo cat "$BOOT_CMDLINE" | tr ' ' '\n' | grep -c '^splash$' || true)"
    consoleblank_count="$(sudo cat "$BOOT_CMDLINE" | tr ' ' '\n' | grep -c '^consoleblank=0$' || true)"
    if is_yes "$FORCE_RESOLUTION"; then
      [[ "$video_count" == "1" ]] || die "A video= bootparaméterek száma nem egy."
    else
      [[ "$video_count" == "0" ]] || die "Nem várt video= bootparaméter maradt."
    fi
    if is_yes "$ENABLE_SPLASH"; then
      [[ "$splash_count" == "1" ]] || die "A splash bootparaméterek száma nem egy."
    else
      [[ "$splash_count" == "0" ]] || die "Nem várt splash bootparaméter maradt."
    fi
    if is_yes "$ENABLE_BROWSER" && is_yes "$ENABLE_IDLE"; then
      [[ "$consoleblank_count" == "1" ]] ||
        die "A consoleblank=0 bootparaméterek száma nem egy."
    fi
    if sudo cat "$BOOT_CMDLINE" | tr ' ' '\n' | grep -qx 'console=tty3'; then
      die "A korábbi telepítő console=tty3 paramétere nem lett migrálva."
    fi
  fi

  if is_yes "$ENABLE_NETWATCH"; then
    verify_root_file "/etc/systemd/system/rpi-kiosk-netwatch.service"
    bash -n "$KIOSK_BIN_DIR/rpi-kiosk-netwatch" ||
      die "A telepített watchdog szintaktikailag hibás."
    sudo systemctl is-enabled --quiet rpi-kiosk-netwatch.service ||
      die "Az internet-watchdog szolgáltatás nincs engedélyezve."
    sudo systemctl is-active --quiet rpi-kiosk-netwatch.service ||
      die "Az internet-watchdog szolgáltatás nem fut."
  fi

  if is_yes "$ENABLE_CEC"; then
    verify_root_file "/etc/systemd/system/rpi-kiosk-cec.service"
    bash -n "$KIOSK_BIN_DIR/rpi-kiosk-cec" ||
      die "A telepített CEC-segéd szintaktikailag hibás."
    sudo systemctl is-enabled --quiet rpi-kiosk-cec.service ||
      die "A CEC szolgáltatás nincs engedélyezve."
  fi

  if is_yes "$ENABLE_GREETD"; then
    sudo systemctl is-enabled --quiet greetd.service ||
      die "A greetd szolgáltatás nincs engedélyezve."
  fi

  if command -v systemd-analyze >/dev/null 2>&1; then
    local units=()
    is_yes "$ENABLE_NETWATCH" && units+=(/etc/systemd/system/rpi-kiosk-netwatch.service)
    is_yes "$ENABLE_CEC" && units+=(/etc/systemd/system/rpi-kiosk-cec.service)
    if ((${#units[@]})); then
      run_step "systemd egységek ellenőrzése" sudo systemd-analyze verify "${units[@]}"
    fi
  fi

  success "A telepített komponensek ellenőrzése rendben."
}
