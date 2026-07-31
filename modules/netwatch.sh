#!/usr/bin/env bash

netwatch_environment_content() {
  cat <<EOF
# RPI KIOSK – a telepítő által kezelt fájl
CHECK_INTERVAL_SECONDS=30
REBOOT_AFTER_MINUTES=$(shell_quote "$NETWATCH_REBOOT_MINUTES")
PING_TARGETS=$(shell_quote "1.1.1.1 8.8.8.8")
HTTP_CHECK_URL=$(shell_quote "https://connectivitycheck.gstatic.com/generate_204")
EOF
}

cleanup_legacy_netwatch() {
  if systemctl cat kiosk-netwatch.service >/dev/null 2>&1; then
    run_optional_step "Régi internet-watchdog leállítása" \
      sudo systemctl disable --now kiosk-netwatch.service
  fi
  remove_root_file "/etc/systemd/system/kiosk-netwatch.service"
  remove_root_file "/usr/local/bin/kiosk-netwatch.sh"
  remove_root_file "/etc/default/kiosk-netwatch"
}

enable_netwatch() {
  cleanup_legacy_netwatch
  install_root_file \
    "$SCRIPT_DIR/templates/rpi-kiosk-netwatch" \
    "$KIOSK_BIN_DIR/rpi-kiosk-netwatch" \
    0755
  write_root_content \
    "$KIOSK_ETC_DIR/netwatch.env" \
    0644 \
    "$(netwatch_environment_content)"
  install_root_file \
    "$SCRIPT_DIR/templates/systemd/rpi-kiosk-netwatch.service" \
    "/etc/systemd/system/rpi-kiosk-netwatch.service" \
    0644

  run_step "systemd konfiguráció újratöltése" sudo systemctl daemon-reload
  run_step "Internet-watchdog engedélyezése" \
    sudo systemctl enable rpi-kiosk-netwatch.service
  run_step "Internet-watchdog újraindítása" \
    sudo systemctl restart rpi-kiosk-netwatch.service
  write_state_flag "netwatch-managed"
}

disable_netwatch() {
  cleanup_legacy_netwatch
  if systemctl cat rpi-kiosk-netwatch.service >/dev/null 2>&1; then
    run_optional_step "Internet-watchdog leállítása" \
      sudo systemctl disable --now rpi-kiosk-netwatch.service
  fi
  remove_root_file "/etc/systemd/system/rpi-kiosk-netwatch.service"
  remove_root_file "$KIOSK_BIN_DIR/rpi-kiosk-netwatch"
  remove_root_file "$KIOSK_ETC_DIR/netwatch.env"
  remove_state_flag "netwatch-managed"
  sudo systemctl daemon-reload
  sudo systemctl reset-failed rpi-kiosk-netwatch.service >/dev/null 2>&1 || true
}

apply_netwatch_module() {
  section "Internet-watchdog"
  if is_yes "$ENABLE_NETWATCH"; then
    enable_netwatch
    success "Internet-watchdog aktív; reboot ${NETWATCH_REBOOT_MINUTES} perc folyamatos kimaradás után."
  else
    disable_netwatch
    info "Kezelt internet-watchdog eltávolítva."
  fi
}
