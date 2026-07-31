#!/usr/bin/env bash

state_value() {
  local file="$1"
  local key="$2"
  sudo awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file" 2>/dev/null || true
}

cleanup_legacy_cec() {
  if systemctl cat cec-setup.service >/dev/null 2>&1; then
    run_optional_step "Régi HDMI-CEC szolgáltatás leállítása" \
      sudo systemctl disable --now cec-setup.service
  fi
  remove_root_file "/etc/systemd/system/cec-setup.service"
  remove_root_file "/usr/local/bin/cec-setup.sh"
  remove_root_file "/etc/rc_keymaps/custom-cec.toml"
}

cmdline_has_token() {
  local line="$1"
  local wanted="$2"
  local token
  # shellcheck disable=SC2086
  for token in $line; do
    [[ "$token" == "$wanted" ]] && return 0
  done
  return 1
}

cmdline_without_exact_token() {
  local line="$1"
  local unwanted="$2"
  local token output=""
  # shellcheck disable=SC2086
  for token in $line; do
    [[ "$token" == "$unwanted" ]] && continue
    output+="${output:+ }$token"
  done
  printf '%s\n' "$output"
}

cmdline_without_key() {
  local line="$1"
  local key="$2"
  local token output=""
  # shellcheck disable=SC2086
  for token in $line; do
    [[ "$token" == "$key="* ]] && continue
    output+="${output:+ }$token"
  done
  printf '%s\n' "$output"
}

cmdline_append_token() {
  local line="$1"
  local token="$2"
  if [[ -n "$line" ]]; then
    printf '%s %s\n' "$line" "$token"
  else
    printf '%s\n' "$token"
  fi
}

apply_cmdline_settings() {
  [[ -f "$BOOT_CMDLINE" ]] || {
    warn "A cmdline.txt nem található; bootparaméterek kihagyva."
    return 0
  }

  local state_file="$KIOSK_STATE_DIR/cmdline.state"
  local old_video="" old_quiet="n" old_splash="n" old_plymouth="n"
  local managed_consoleblank="n" previous_consoleblank=""
  if sudo test -s "$state_file"; then
    old_video="$(state_value "$state_file" VIDEO_TOKEN)"
    old_quiet="$(state_value "$state_file" ADDED_QUIET)"
    old_splash="$(state_value "$state_file" ADDED_SPLASH)"
    old_plymouth="$(state_value "$state_file" ADDED_PLYMOUTH)"
    managed_consoleblank="$(state_value "$state_file" MANAGED_CONSOLEBLANK)"
    previous_consoleblank="$(state_value "$state_file" PREVIOUS_CONSOLEBLANK)"
  fi

  local line
  line="$(sudo cat "$BOOT_CMDLINE" | tr -d '\r' | head -n 1)"

  # A korábbi telepítő minden console= bejegyzést console=tty3-ra cserélt.
  # Ezt célzottan migráljuk vissza tty1-re, más (például soros) konzolt nem érintve.
  if cmdline_has_token "$line" "console=tty3"; then
    line="$(cmdline_without_exact_token "$line" "console=tty3")"
    if ! cmdline_has_token "$line" "console=tty1"; then
      line="$(cmdline_append_token "$line" "console=tty1")"
    fi
  fi

  [[ -n "$old_video" ]] && line="$(cmdline_without_exact_token "$line" "$old_video")"
  [[ "$old_quiet" == "y" ]] && line="$(cmdline_without_exact_token "$line" quiet)"
  [[ "$old_splash" == "y" ]] && line="$(cmdline_without_exact_token "$line" splash)"
  [[ "$old_plymouth" == "y" ]] && line="$(cmdline_without_exact_token "$line" plymouth.ignore-serial-consoles)"

  # Ezeket a kulcsokat ez a telepítő teljes egészében kezeli. Így az első
  # új verziós futás a régi telepítő maradványait is duplikáció nélkül migrálja.
  line="$(cmdline_without_key "$line" video)"
  line="$(cmdline_without_exact_token "$line" splash)"
  line="$(cmdline_without_exact_token "$line" plymouth.ignore-serial-consoles)"

  local video_token=""
  if is_yes "$FORCE_RESOLUTION"; then
    video_token="video=${DISPLAY_OUTPUT}:${DISPLAY_MODE}"
    line="$(cmdline_append_token "$line" "$video_token")"
  fi

  local added_quiet="n" added_splash="n" added_plymouth="n"
  if is_yes "$ENABLE_SPLASH"; then
    if ! cmdline_has_token "$line" quiet; then
      line="$(cmdline_append_token "$line" quiet)"
      added_quiet="y"
    fi
    if ! cmdline_has_token "$line" splash; then
      line="$(cmdline_append_token "$line" splash)"
      added_splash="y"
    fi
    if ! cmdline_has_token "$line" plymouth.ignore-serial-consoles; then
      line="$(cmdline_append_token "$line" plymouth.ignore-serial-consoles)"
      added_plymouth="y"
    fi
  fi

  if is_yes "$ENABLE_BROWSER" && is_yes "$ENABLE_IDLE"; then
    if [[ "$managed_consoleblank" != "y" ]]; then
      local token
      # shellcheck disable=SC2086
      for token in $line; do
        if [[ "$token" == consoleblank=* ]]; then
          previous_consoleblank="$token"
          break
        fi
      done
    fi
    line="$(cmdline_without_key "$line" consoleblank)"
    line="$(cmdline_append_token "$line" "consoleblank=0")"
    managed_consoleblank="y"
  elif [[ "$managed_consoleblank" == "y" ]]; then
    line="$(cmdline_without_key "$line" consoleblank)"
    if [[ -n "$previous_consoleblank" ]]; then
      line="$(cmdline_append_token "$line" "$previous_consoleblank")"
    fi
    managed_consoleblank="n"
    previous_consoleblank=""
  fi

  printf '%s\n' "$line" | sudo tee "$BOOT_CMDLINE" >/dev/null
  local state
  state="VIDEO_TOKEN=$video_token
ADDED_QUIET=$added_quiet
ADDED_SPLASH=$added_splash
ADDED_PLYMOUTH=$added_plymouth
MANAGED_CONSOLEBLANK=$managed_consoleblank
PREVIOUS_CONSOLEBLANK=$previous_consoleblank
"
  write_root_content "$state_file" 0644 "$state"
  success "Kernel parancssor frissítve, ismétlődő kezelt paraméterek nélkül."
}

apply_boot_config() {
  [[ -f "$BOOT_CONFIG" ]] || {
    warn "A config.txt nem található; firmware-beállítások kihagyva."
    return 0
  }

  local content=""
  if is_yes "$ENABLE_SPLASH"; then
    content+="# Firmware szivárványkép letiltása a Plymouth splash számára"$'\n'
    content+="disable_splash=1"$'\n'
  fi
  if is_yes "$ENABLE_HDMI_AUDIO"; then
    content+="# Analóg hang letiltása; HDMI/PipeWire marad elsődleges"$'\n'
    content+="dtparam=audio=off"$'\n'
  fi

  update_managed_block "$BOOT_CONFIG" "$content" y 0644
  success "Firmware konfiguráció frissítve kezelt blokkban."
}

enable_cec() {
  install_root_file \
    "$SCRIPT_DIR/templates/cec/custom-cec.toml" \
    "/etc/rc_keymaps/rpi-kiosk-cec.toml" \
    0644
  install_root_file \
    "$SCRIPT_DIR/templates/cec/rpi-kiosk-cec" \
    "$KIOSK_BIN_DIR/rpi-kiosk-cec" \
    0755
  install_root_file \
    "$SCRIPT_DIR/templates/systemd/rpi-kiosk-cec.service" \
    "/etc/systemd/system/rpi-kiosk-cec.service" \
    0644

  run_step "systemd konfiguráció újratöltése" sudo systemctl daemon-reload
  run_step "HDMI-CEC szolgáltatás engedélyezése" \
    sudo systemctl enable rpi-kiosk-cec.service
  write_state_flag "cec-managed"
}

disable_cec() {
  if systemctl cat rpi-kiosk-cec.service >/dev/null 2>&1; then
    run_optional_step "HDMI-CEC szolgáltatás letiltása" \
      sudo systemctl disable --now rpi-kiosk-cec.service
  fi
  remove_root_file "/etc/systemd/system/rpi-kiosk-cec.service"
  remove_root_file "$KIOSK_BIN_DIR/rpi-kiosk-cec"
  remove_root_file "/etc/rc_keymaps/rpi-kiosk-cec.toml"
  remove_state_flag "cec-managed"
  sudo systemctl daemon-reload
}

apply_cec() {
  cleanup_legacy_cec
  if is_yes "$ENABLE_CEC"; then
    enable_cec
    success "HDMI-CEC támogatás konfigurálva."
  else
    disable_cec
    info "Kezelt HDMI-CEC támogatás kikapcsolva."
  fi
}

apply_hardware_module() {
  section "Kijelző, hang és HDMI-CEC"
  apply_boot_config
  apply_cmdline_settings
  apply_cec
}
