#!/usr/bin/env bash

update_labwc_cursor_binding() {
  local mode="$1"
  local config_dir="$HOME_DIR/.config/labwc"
  local rc_xml="$config_dir/rc.xml"
  install -d -m 0755 "$config_dir"

  python3 - "$rc_xml" "$mode" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
mode = sys.argv[2]
begin = "<!-- RPI_KIOSK_CURSOR_BEGIN -->"
end = "<!-- RPI_KIOSK_CURSOR_END -->"
legacy_begin = "<!-- KIOSK_HIDE_CURSOR_BEGIN -->"
legacy_end = "<!-- KIOSK_HIDE_CURSOR_END -->"

block = f'''  {begin}
  <keybind key="W-h">
    <action name="HideCursor"/>
    <action name="WarpCursor" to="output" x="1" y="1"/>
  </keybind>
  {end}'''

minimal = f'''<?xml version="1.0"?>
<labwc_config>
  <keyboard>
{block}
  </keyboard>
</labwc_config>
'''

text = path.read_text(encoding="utf-8") if path.exists() else ""
for start, finish in ((begin, end), (legacy_begin, legacy_end)):
    text = re.sub(
        rf"\n?[ \t]*{re.escape(start)}.*?{re.escape(finish)}[ \t]*\n?",
        "\n",
        text,
        flags=re.S,
    )

text = re.sub(
    r'\n?[ \t]*<keybind\s+key="W-h">.*?<action\s+name="HideCursor"\s*/>.*?</keybind>[ \t]*\n?',
    "\n",
    text,
    flags=re.S,
)
text = re.sub(r"\n{3,}", "\n\n", text)

if mode == "disable":
    if path.exists():
        path.write_text(text, encoding="utf-8")
        import xml.etree.ElementTree as ET
        ET.parse(path)
    raise SystemExit(0)

if not text.strip():
    path.write_text(minimal, encoding="utf-8")
elif re.search(r"<keyboard\b[^>]*/>", text):
    text = re.sub(
        r"<keyboard\b[^>]*/>",
        f"<keyboard>\n{block}\n</keyboard>",
        text,
        count=1,
    )
    path.write_text(text, encoding="utf-8")
elif "</keyboard>" in text:
    text = text.replace("</keyboard>", f"{block}\n</keyboard>", 1)
    path.write_text(text, encoding="utf-8")
elif "</labwc_config>" in text:
    text = text.replace(
        "</labwc_config>",
        f"  <keyboard>\n{block}\n  </keyboard>\n</labwc_config>",
        1,
    )
    path.write_text(text, encoding="utf-8")
else:
    raise SystemExit("A meglévő rc.xml nem értelmezhető biztonságosan.")

import xml.etree.ElementTree as ET
ET.parse(path)
PY
}

apply_wallpaper() {
  if is_yes "$ENABLE_WALLPAPER"; then
    install_root_file \
      "$SCRIPT_DIR/_assets/wallpaper/wallpaper.png" \
      "$KIOSK_SHARE_DIR/wallpaper.png" \
      0644
    write_state_flag "wallpaper-managed"
    success "Alu-Technika háttér telepítve."
  else
    remove_root_file "$KIOSK_SHARE_DIR/wallpaper.png"
    remove_state_flag "wallpaper-managed"
    info "Kezelt háttérkép kikapcsolva."
  fi
}

apply_cursor_hide() {
  if is_yes "$ENABLE_CURSOR_HIDE"; then
    update_labwc_cursor_binding enable
    success "Automatikus kurzorelrejtés konfigurálva."
  else
    update_labwc_cursor_binding disable
    info "Automatikus kurzorelrejtés kikapcsolva."
  fi
}

remember_previous_plymouth_theme() {
  if has_state_flag "splash-managed"; then
    return 0
  fi
  local previous
  previous="$(sudo plymouth-set-default-theme 2>/dev/null || true)"
  [[ -n "$previous" ]] || previous="spinner"
  write_root_content "$KIOSK_STATE_DIR/previous-plymouth-theme" 0644 "$previous"$'\n'
}

enable_splash_theme() {
  remember_previous_plymouth_theme
  local theme_dir="/usr/share/plymouth/themes/rpi-kiosk"
  install_root_file \
    "$SCRIPT_DIR/templates/plymouth/rpi-kiosk.plymouth" \
    "$theme_dir/rpi-kiosk.plymouth" \
    0644
  install_root_file \
    "$SCRIPT_DIR/templates/plymouth/rpi-kiosk.script" \
    "$theme_dir/rpi-kiosk.script" \
    0644
  install_root_file \
    "$SCRIPT_DIR/_assets/splashscreens/splash.png" \
    "$theme_dir/splash.png" \
    0644

  run_step "Plymouth kioszk-téma aktiválása" \
    sudo plymouth-set-default-theme -R rpi-kiosk
  write_state_flag "splash-managed"
}

disable_splash_theme() {
  if ! has_state_flag "splash-managed"; then
    return 0
  fi

  local previous="spinner"
  if sudo test -s "$KIOSK_STATE_DIR/previous-plymouth-theme"; then
    previous="$(sudo cat "$KIOSK_STATE_DIR/previous-plymouth-theme" | tr -d '\r\n')"
  fi
  if [[ -d "/usr/share/plymouth/themes/$previous" ]]; then
    run_optional_step "Korábbi Plymouth-téma visszaállítása" \
      sudo plymouth-set-default-theme -R "$previous"
  fi
  sudo rm -rf -- "/usr/share/plymouth/themes/rpi-kiosk"
  remove_state_flag "splash-managed"
}

apply_splash() {
  if is_yes "$ENABLE_SPLASH"; then
    enable_splash_theme
    success "Egyedi splash képernyő telepítve."
  else
    disable_splash_theme
    info "Kezelt splash képernyő kikapcsolva."
  fi
}

build_labwc_autostart_content() {
  local content="# Alu-Technika RPI KIOSK – automatikusan generált beállítások"
  local display_command=""

  if is_yes "$ENABLE_WALLPAPER"; then
    content+=$'\n'"swaybg -m fill -i $KIOSK_SHARE_DIR/wallpaper.png &"
  fi

  if is_yes "$FORCE_RESOLUTION" || is_yes "$ENABLE_ROTATION"; then
    display_command="wlr-randr --output $DISPLAY_OUTPUT"
    is_yes "$FORCE_RESOLUTION" && display_command+=" --mode $DISPLAY_MODE"
    is_yes "$ENABLE_ROTATION" && display_command+=" --transform $DISPLAY_TRANSFORM"
    content+=$'\n'"(sleep 2; $display_command) >/tmp/rpi-kiosk-display.log 2>&1 &"
  fi

  if is_yes "$ENABLE_BROWSER"; then
    content+=$'\n'"(sleep 3; $KIOSK_BIN_DIR/rpi-kiosk-browser work) &"
    if is_yes "$ENABLE_IDLE"; then
      content+=$'\n'"(sleep 6; swayidle -w timeout $IDLE_TIMEOUT '$KIOSK_BIN_DIR/rpi-kiosk-browser idle' resume '$KIOSK_BIN_DIR/rpi-kiosk-browser work') >/tmp/rpi-kiosk-idle.log 2>&1 &"
    fi
  fi

  if is_yes "$ENABLE_CURSOR_HIDE"; then
    content+=$'\n'"(sleep 5; wtype -M logo -k h -m logo) >/dev/null 2>&1 &"
  fi

  printf '%s\n' "$content"
}

disable_conflicting_screen_blanking() {
  local autostart="$1"
  [[ -f "$autostart" ]] || return 0
  if ! grep -Eqi 'swayidle.*wlopm[[:space:]]+--off' "$autostart"; then
    return 0
  fi

  if ! sudo test -f "$KIOSK_STATE_DIR/labwc-autostart.before-screen-blanking"; then
    sudo install -m 0600 \
      "$autostart" \
      "$KIOSK_STATE_DIR/labwc-autostart.before-screen-blanking"
  fi

  local cleaned="$RUN_TMP/autostart-no-blanking"
  awk '
    tolower($0) ~ /swayidle/ && tolower($0) ~ /wlopm[[:space:]]+--off/ { next }
    { print }
  ' "$autostart" >"$cleaned"
  install -m 0755 "$cleaned" "$autostart"
  info "A Raspberry Pi OS kijelző-kikapcsoló swayidle sora eltávolítva (mentés készült)."
}

ensure_autostart_shebang() {
  local autostart="$1"
  if [[ -s "$autostart" ]] && head -n 1 "$autostart" | grep -q '^#!'; then
    return 0
  fi

  local output="$RUN_TMP/autostart-with-shebang"
  printf '#!/bin/sh\n' >"$output"
  [[ -f "$autostart" ]] && cat "$autostart" >>"$output"
  install -m 0755 "$output" "$autostart"
}

apply_labwc_autostart() {
  section "labwc automatikus indítás"
  local autostart="$HOME_DIR/.config/labwc/autostart"
  local content
  install -d -m 0755 "$(dirname "$autostart")"
  ensure_autostart_shebang "$autostart"
  disable_conflicting_screen_blanking "$autostart"
  content="$(build_labwc_autostart_content)"
  update_managed_block "$autostart" "$content" n 0755
  success "labwc autostart frissítve duplikáció nélkül."
}

apply_appearance_module() {
  section "Megjelenés"
  apply_wallpaper
  apply_cursor_hide
  apply_splash
}
