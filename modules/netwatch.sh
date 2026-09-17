#!/usr/bin/env bash

netwatch_environment_content() {
  cat <<EOF
# RPI KIOSK – a telepítő által kezelt fájl
CHECK_INTERVAL_SECONDS=30
REBOOT_AFTER_MINUTES=$(shell_quote "$NETWATCH_REBOOT_MINUTES")
PING_TARGETS=$(shell_quote "1.1.1.1 8.8.8.8")
HTTP_CHECK_URL=$(shell_quote "https://connectivitycheck.gstatic.com/generate_204")
BROWSER_USER=$(shell_quote "$CURRENT_USER")
BROWSER_WATCHDOG_ENABLED=$(shell_quote "$ENABLE_BROWSER")
BROWSER_FAIL_CHECKS=3
BROWSER_RESTART_FAILURE_LIMIT=3
BROWSER_RESTART_SETTLE_SECONDS=12
WORK_URL=$(shell_quote "$WORK_URL")
IDLE_URL=$(shell_quote "$IDLE_URL")
WORK_DEBUG_PORT=9222
IDLE_DEBUG_PORT=9223
EOF
}

cleanup_legacy_netwatch() {
  if systemctl cat kiosk-netwatch.service >/dev/null 2>&1; then
    run_optional_step "Régi internet-watchdog leállítása" \
      sudo systemctl disable --now kiosk-netwatch.service
  fi
  remove_root_file "/etc/systemd/system/kiosk-netwatch.service"
  remove_root_file "/usr/local/bin/kiosk-netwatch.sh"
  remove_root_file "/usr/local/libexec/kiosk-chromium-health.py"
  remove_root_file "/etc/default/kiosk-netwatch"
}

enable_persistent_kiosk_journal() {
  install_root_file \
    "$SCRIPT_DIR/templates/journald/90-rpi-kiosk-persistent.conf" \
    "/etc/systemd/journald.conf.d/90-rpi-kiosk-persistent.conf" \
    0644
  sudo install -d -m 2755 -o root -g systemd-journal /var/log/journal
  run_step "Persistent KIOSK journal aktiválása" sudo systemctl restart systemd-journald.service
  run_optional_step "Journal lemezre ürítése" sudo journalctl --flush
  write_state_flag "persistent-journal-managed"
}

disable_persistent_kiosk_journal() {
  if has_state_flag "persistent-journal-managed"; then
    remove_root_file "/etc/systemd/journald.conf.d/90-rpi-kiosk-persistent.conf"
    run_optional_step "systemd-journald újraindítása" sudo systemctl restart systemd-journald.service
    remove_state_flag "persistent-journal-managed"
  fi
}

enable_netwatch() {
  cleanup_legacy_netwatch
  install_root_file \
    "$SCRIPT_DIR/templates/rpi-kiosk-netwatch" \
    "$KIOSK_BIN_DIR/rpi-kiosk-netwatch" \
    0755
  install_root_file \
    "$SCRIPT_DIR/templates/rpi-kiosk-chromium-health.py" \
    "/usr/local/libexec/rpi-kiosk-chromium-health" \
    0755
  write_root_content \
    "$KIOSK_ETC_DIR/netwatch.env" \
    0644 \
    "$(netwatch_environment_content)"
  install_root_file \
    "$SCRIPT_DIR/templates/systemd/rpi-kiosk-netwatch.service" \
    "/etc/systemd/system/rpi-kiosk-netwatch.service" \
    0644

  enable_persistent_kiosk_journal
  run_step "systemd konfiguráció újratöltése" sudo systemctl daemon-reload
  run_step "KIOSK watchdog engedélyezése" \
    sudo systemctl enable rpi-kiosk-netwatch.service
  run_step "KIOSK watchdog újraindítása" \
    sudo systemctl restart rpi-kiosk-netwatch.service
  write_state_flag "netwatch-managed"
}

disable_netwatch() {
  cleanup_legacy_netwatch
  if systemctl cat rpi-kiosk-netwatch.service >/dev/null 2>&1; then
    run_optional_step "KIOSK watchdog leállítása" \
      sudo systemctl disable --now rpi-kiosk-netwatch.service
  fi
  remove_root_file "/etc/systemd/system/rpi-kiosk-netwatch.service"
  remove_root_file "$KIOSK_BIN_DIR/rpi-kiosk-netwatch"
  remove_root_file "/usr/local/libexec/rpi-kiosk-chromium-health"
  remove_root_file "$KIOSK_ETC_DIR/netwatch.env"
  remove_state_flag "netwatch-managed"
  disable_persistent_kiosk_journal
  sudo systemctl daemon-reload
  sudo systemctl reset-failed rpi-kiosk-netwatch.service >/dev/null 2>&1 || true
}

apply_netwatch_module() {
  section "KIOSK watchdog"
  if is_yes "$ENABLE_NETWATCH"; then
    enable_netwatch
    if is_yes "$ENABLE_BROWSER"; then
      success "Internet- és Chromium renderer watchdog aktív; 3 hibás renderer-ellenőrzés után Chromium-helyreállítás indul."
    else
      success "Internet-watchdog aktív; reboot ${NETWATCH_REBOOT_MINUTES} perc folyamatos kimaradás után."
    fi
  else
    disable_netwatch
    info "Kezelt KIOSK watchdog eltávolítva."
  fi
}
