#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_ROOT
cd "$TEST_ROOT"

shell_files=(
  kiosk_setup.sh
  lib/core.sh
  modules/packages.sh
  modules/session.sh
  modules/browser.sh
  modules/appearance.sh
  modules/hardware.sh
  modules/netwatch.sh
  templates/rpi-kiosk-browser
  templates/rpi-kiosk-netwatch
  templates/cec/rpi-kiosk-cec
)

for file in "${shell_files[@]}"; do
  bash -n "$file"
done

python3 - <<'PY'
from pathlib import Path
compile(Path("templates/rpi-kiosk-chromium-health.py").read_text(), "templates/rpi-kiosk-chromium-health.py", "exec")
PY

grep -Fq 'Storage=persistent' templates/journald/90-rpi-kiosk-persistent.conf
grep -Fq 'SystemMaxUse=64M' templates/journald/90-rpi-kiosk-persistent.conf
grep -Fq -- '--remote-debugging-address=127.0.0.1' templates/rpi-kiosk-browser
grep -Fq 'force-restart' templates/rpi-kiosk-browser
grep -Fq 'renderer_healthy' templates/rpi-kiosk-netwatch

# shellcheck source=lib/core.sh
source "$TEST_ROOT/lib/core.sh"
# shellcheck source=modules/hardware.sh
source "$TEST_ROOT/modules/hardware.sh"
# shellcheck source=modules/appearance.sh
source "$TEST_ROOT/modules/appearance.sh"

RUN_TMP="$(mktemp -d)"
HOME_DIR="$RUN_TMP/home"
RUN_LOG="$RUN_TMP/run.log"
mkdir -p "$HOME_DIR"
cleanup_test() {
  if [[ -n "${RPI_KIOSK_CONFIG_FILE:-}" ]]; then
    bash "$TEST_ROOT/templates/rpi-kiosk-browser" stop >/dev/null 2>&1 || true
  fi
  rm -rf -- "$RUN_TMP"
}
trap cleanup_test EXIT

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$expected" != "$actual" ]]; then
    printf 'HIBA: %s\nVárt: %s\nKapott: %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_count() {
  local expected="$1"
  local pattern="$2"
  local file="$3"
  local actual
  actual="$(grep -Fc "$pattern" "$file" || true)"
  assert_equals "$expected" "$actual" "$pattern előfordulása"
}

validate_http_url "http://192.168.1.40:18006"
validate_http_url "https://kiosk.example.local/path?a=1"
assert_equals "192.168.1.40" "$(url_host "http://192.168.1.40:18006/app")" "URL host kinyerése"
if validate_http_url "javascript:alert(1)"; then
  echo "HIBA: veszélyes URL átment a validáción." >&2
  exit 1
fi

managed_file="$RUN_TMP/autostart"
cat >"$managed_file" <<'EOF'
eredeti sor
#KIOSKPARANCS_BEGIN
régi kioszk sor
#KIOSKPARANCS_END
EOF

update_managed_block "$managed_file" "első új sor" n 0644
update_managed_block "$managed_file" "második új sor" n 0644
assert_count 1 "$MANAGED_BEGIN" "$managed_file"
assert_count 1 "$MANAGED_END" "$managed_file"
assert_count 0 "$LEGACY_BEGIN" "$managed_file"
assert_count 0 "első új sor" "$managed_file"
assert_count 1 "második új sor" "$managed_file"
assert_count 1 "eredeti sor" "$managed_file"
ensure_autostart_shebang "$managed_file"
assert_equals "#!/bin/sh" "$(head -n 1 "$managed_file")" "labwc autostart shebang"
[[ -x "$managed_file" ]] || {
  echo "HIBA: a labwc autostart tesztfájl nem végrehajtható." >&2
  exit 1
}

line="root=/dev/mmcblk0p2 quiet video=HDMI-A-1:1280x720@60 splash"
line="$(cmdline_without_key "$line" video)"
assert_equals "root=/dev/mmcblk0p2 quiet splash" "$line" "video kulcs eltávolítása"
line="$(cmdline_without_exact_token "$line" splash)"
assert_equals "root=/dev/mmcblk0p2 quiet" "$line" "pontos token eltávolítása"
line="$(cmdline_append_token "$line" "video=HDMI-A-1:1920x1080@60")"
assert_equals \
  "root=/dev/mmcblk0p2 quiet video=HDMI-A-1:1920x1080@60" \
  "$line" \
  "token hozzáadása"
line="$(cmdline_append_token "$line" "consoleblank=600")"
line="$(cmdline_without_key "$line" consoleblank)"
line="$(cmdline_append_token "$line" "consoleblank=0")"
assert_equals \
  "root=/dev/mmcblk0p2 quiet video=HDMI-A-1:1920x1080@60 consoleblank=0" \
  "$line" \
  "konzolblankolás felülírása"
legacy_console_line="root=/dev/mmcblk0p2 console=tty3 quiet"
legacy_console_line="$(cmdline_without_exact_token "$legacy_console_line" "console=tty3")"
legacy_console_line="$(cmdline_append_token "$legacy_console_line" "console=tty1")"
assert_equals \
  "root=/dev/mmcblk0p2 quiet console=tty1" \
  "$legacy_console_line" \
  "régi tty3 konzol migrációja"

# A Chromium-vezérlő integrációs tesztje egy izolált, alvó próbafolyamattal.
fake_chromium="$RUN_TMP/fake-chromium"
cat >"$fake_chromium" <<'EOF'
#!/usr/bin/env bash
trap 'exit 0' TERM INT
while true; do sleep 1; done
EOF
chmod +x "$fake_chromium"

if ! command -v flock >/dev/null 2>&1 || ! command -v setsid >/dev/null 2>&1; then
  mkdir -p "$RUN_TMP/test-bin"
fi
if ! command -v flock >/dev/null 2>&1; then
  cat >"$RUN_TMP/test-bin/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$RUN_TMP/test-bin/flock"
fi
if ! command -v setsid >/dev/null 2>&1; then
  cat >"$RUN_TMP/test-bin/setsid" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
  chmod +x "$RUN_TMP/test-bin/setsid"
fi
if [[ -d "$RUN_TMP/test-bin" ]]; then
  PATH="$RUN_TMP/test-bin:$PATH"
  export PATH
fi

RPI_KIOSK_CONFIG_FILE="$RUN_TMP/browser.env"
XDG_RUNTIME_DIR="$RUN_TMP/runtime"
XDG_STATE_HOME="$RUN_TMP/state"
export RPI_KIOSK_CONFIG_FILE XDG_RUNTIME_DIR XDG_STATE_HOME
cat >"$RPI_KIOSK_CONFIG_FILE" <<EOF
WORK_URL=http://127.0.0.1/work
IDLE_URL=http://127.0.0.1/idle
IDLE_ENABLED=y
INCOGNITO_MODE=n
WAIT_FOR_NETWORK=n
PING_HOST=127.0.0.1
NETWORK_WAIT_SECONDS=2
WORK_DEBUG_PORT=9222
IDLE_DEBUG_PORT=9223
CHROMIUM_BIN=$fake_chromium
EOF

bash "$TEST_ROOT/templates/rpi-kiosk-browser" work
work_pid="$(<"$XDG_RUNTIME_DIR/rpi-kiosk/browser-work.pid")"
kill -0 "$work_pid"
tr '\0' ' ' <"/proc/$work_pid/cmdline" | grep -Fq -- '--remote-debugging-address=127.0.0.1'
tr '\0' ' ' <"/proc/$work_pid/cmdline" | grep -Fq -- '--remote-debugging-port=9222'

bash "$TEST_ROOT/templates/rpi-kiosk-browser" idle
idle_pid="$(<"$XDG_RUNTIME_DIR/rpi-kiosk/browser-idle.pid")"
kill -0 "$idle_pid"
tr '\0' ' ' <"/proc/$idle_pid/cmdline" | grep -Fq -- '--remote-debugging-port=9223'
if kill -0 "$work_pid" 2>/dev/null; then
  echo "HIBA: a work Chromium-folyamat nem állt le idle váltáskor." >&2
  exit 1
fi

bash "$TEST_ROOT/templates/rpi-kiosk-browser" work
second_work_pid="$(<"$XDG_RUNTIME_DIR/rpi-kiosk/browser-work.pid")"
kill -0 "$second_work_pid"
if kill -0 "$idle_pid" 2>/dev/null; then
  echo "HIBA: az idle Chromium-folyamat nem állt le work váltáskor." >&2
  exit 1
fi

bash "$TEST_ROOT/templates/rpi-kiosk-browser" force-restart
restarted_work_pid="$(<"$XDG_RUNTIME_DIR/rpi-kiosk/browser-work.pid")"
kill -0 "$restarted_work_pid"
if [[ "$restarted_work_pid" == "$second_work_pid" ]]; then
  echo "HIBA: a force-restart nem indított új Chromium-folyamatot." >&2
  exit 1
fi
if kill -0 "$second_work_pid" 2>/dev/null; then
  echo "HIBA: a régi Chromium-folyamat force-restart után is fut." >&2
  exit 1
fi

bash "$TEST_ROOT/templates/rpi-kiosk-browser" stop
if kill -0 "$restarted_work_pid" 2>/dev/null; then
  echo "HIBA: a work Chromium-folyamat stop után is fut." >&2
  exit 1
fi

if { run_step "szándékosan hibás tesztlépés" bash -c 'exit 23'; } 2>/dev/null; then
  echo "HIBA: run_step elnyelte a hibás kilépési kódot." >&2
  exit 1
fi

printf 'Minden telepítőteszt sikeres.\n'
