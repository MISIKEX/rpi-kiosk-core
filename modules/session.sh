#!/usr/bin/env bash

apply_seatd() {
  if ! is_yes "$ENABLE_WAYLAND"; then
    return 0
  fi

  if systemctl cat seatd.service >/dev/null 2>&1; then
    run_optional_step "seatd szolgáltatás engedélyezése" \
      sudo systemctl enable seatd.service
  fi

  if getent group seat >/dev/null 2>&1 &&
    ! id -nG "$CURRENT_USER" | tr ' ' '\n' | grep -qx seat; then
    sudo usermod -aG seat "$CURRENT_USER"
    info "A '$CURRENT_USER' felhasználó bekerült a seat csoportba; ez újraindítás után érvényes."
  fi
}

detect_legacy_managed_greetd() {
  has_state_flag "greetd-managed" && return 0
  sudo test -f "/etc/greetd/config.toml" || return 1
  if sudo grep -Fq "RPI KIOSK" "/etc/greetd/config.toml"; then
    return 0
  fi
  sudo grep -Fq 'command = "/usr/bin/labwc"' "/etc/greetd/config.toml" &&
    sudo grep -Fq "user = \"$CURRENT_USER\"" "/etc/greetd/config.toml"
}

enable_greetd_session() {
  local config
  if ! has_state_flag "greetd-managed" &&
    ! detect_legacy_managed_greetd &&
    sudo test -f "/etc/greetd/config.toml"; then
    sudo install -D -m 0600 \
      "/etc/greetd/config.toml" \
      "$KIOSK_STATE_DIR/greetd-config.backup"
  fi

  config="# RPI KIOSK – a telepítő által kezelt fájl
[terminal]
vt = 7

[default_session]
command = \"dbus-run-session -- /usr/bin/labwc\"
user = \"$CURRENT_USER\"
"
  write_root_content "/etc/greetd/config.toml" 0644 "$config"

  run_step "greetd szolgáltatás engedélyezése" sudo systemctl enable greetd.service
  run_optional_step "Grafikus rendszerindítás beállítása" \
    sudo systemctl set-default graphical.target

  # Csak a működő greetd konfiguráció és sikeres enable után tiltjuk a LightDM-et.
  if systemctl cat lightdm.service >/dev/null 2>&1; then
    run_optional_step "LightDM letiltása a következő indítástól" \
      sudo systemctl disable lightdm.service
  fi
  write_state_flag "greetd-managed"
}

disable_managed_greetd_session() {
  if ! has_state_flag "greetd-managed"; then
    return 0
  fi

  run_optional_step "Korábban kezelt greetd letiltása" \
    sudo systemctl disable greetd.service
  if systemctl cat lightdm.service >/dev/null 2>&1; then
    run_optional_step "LightDM visszaengedélyezése" \
      sudo systemctl enable lightdm.service
  fi
  if sudo test -f "$KIOSK_STATE_DIR/greetd-config.backup"; then
    sudo install -D -m 0644 \
      "$KIOSK_STATE_DIR/greetd-config.backup" \
      "/etc/greetd/config.toml"
    remove_root_file "$KIOSK_STATE_DIR/greetd-config.backup"
  else
    remove_root_file "/etc/greetd/config.toml"
  fi
  remove_state_flag "greetd-managed"
}

apply_session_module() {
  section "Grafikus munkamenet"
  apply_seatd

  if detect_legacy_managed_greetd && ! has_state_flag "greetd-managed"; then
    write_state_flag "greetd-managed"
    info "Korábbi kioszk-greetd konfiguráció felismerve és migrálva."
  fi

  if is_yes "$ENABLE_GREETD"; then
    enable_greetd_session
  else
    disable_managed_greetd_session
    info "A meglévő display manager változatlan marad."
  fi
}
