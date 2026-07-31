#!/usr/bin/env bash

browser_environment_content() {
  cat <<EOF
# RPI KIOSK – a telepítő által kezelt fájl
WORK_URL=$(shell_quote "$WORK_URL")
IDLE_URL=$(shell_quote "$IDLE_URL")
IDLE_ENABLED=$(shell_quote "$ENABLE_IDLE")
INCOGNITO_MODE=$(shell_quote "$ENABLE_INCOGNITO")
WAIT_FOR_NETWORK=$(shell_quote "$ENABLE_NET_WAIT")
PING_HOST=$(shell_quote "$PING_HOST")
NETWORK_WAIT_SECONDS=$(shell_quote "$NETWORK_WAIT_SECONDS")
CHROMIUM_BIN=$(shell_quote "$(command -v chromium || command -v chromium-browser || printf '/usr/bin/chromium')")
EOF
}

install_chromium_policy() {
  local policy='{
  "TranslateEnabled": false,
  "DefaultBrowserSettingEnabled": false,
  "BrowserSignin": 0
}
'
  write_root_content \
    "/etc/chromium/policies/managed/99-rpi-kiosk.json" \
    0644 \
    "$policy"
}

cleanup_legacy_browser_artifacts() {
  remove_root_file "/usr/local/bin/kiosk-browser-switch.sh"
  remove_root_file "/etc/chromium/policies/managed/99-kiosk-disable-translate.json"
  rm -f -- "/tmp/kiosk-browser-mode"
}

apply_browser_module() {
  section "Kioszk böngésző"
  cleanup_legacy_browser_artifacts
  if is_yes "$ENABLE_BROWSER"; then
    install_root_file \
      "$SCRIPT_DIR/templates/rpi-kiosk-browser" \
      "$KIOSK_BIN_DIR/rpi-kiosk-browser" \
      0755
    write_root_content \
      "$KIOSK_ETC_DIR/browser.env" \
      0644 \
      "$(browser_environment_content)"
    install_chromium_policy
    rm -f -- "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/rpi-kiosk/browser-state"
    write_state_flag "browser-managed"
    success "Kioszk böngészővezérlő telepítve."
  else
    remove_root_file "$KIOSK_BIN_DIR/rpi-kiosk-browser"
    remove_root_file "$KIOSK_ETC_DIR/browser.env"
    remove_root_file "/etc/chromium/policies/managed/99-rpi-kiosk.json"
    remove_state_flag "browser-managed"
    info "Kioszk böngésző-autostart kikapcsolva."
  fi
}
