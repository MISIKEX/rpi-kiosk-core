#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=lib/core.sh
source "$SCRIPT_DIR/lib/core.sh"
# shellcheck source=modules/packages.sh
source "$SCRIPT_DIR/modules/packages.sh"
# shellcheck source=modules/session.sh
source "$SCRIPT_DIR/modules/session.sh"
# shellcheck source=modules/browser.sh
source "$SCRIPT_DIR/modules/browser.sh"
# shellcheck source=modules/appearance.sh
source "$SCRIPT_DIR/modules/appearance.sh"
# shellcheck source=modules/hardware.sh
source "$SCRIPT_DIR/modules/hardware.sh"
# shellcheck source=modules/netwatch.sh
source "$SCRIPT_DIR/modules/netwatch.sh"

collect_configuration() {
  section "Telepítési beállítások"

  ASK_APT_UPDATE="$(ask_yes_no "Frissítsük az APT csomaglistát?" "y")"
  ASK_APT_UPGRADE="$(ask_yes_no "Frissítsük a már telepített csomagokat is?" "n")"
  ENABLE_WAYLAND="$(ask_yes_no "Telepítsük/biztosítsuk a labwc Wayland környezetet?" "y")"
  ENABLE_CHROMIUM="$(ask_yes_no "Telepítsük/biztosítsuk a Chromium böngészőt?" "y")"
  ENABLE_GREETD="$(ask_yes_no "Használjunk greetd kioszk-autologint a jelenlegi felhasználóval?" "n")"
  if is_yes "$ENABLE_GREETD" && ! is_yes "$ENABLE_WAYLAND"; then
    warn "A greetd kioszk-munkamenet labwc-t igényel; a Wayland modul automatikusan bekapcsolva."
    ENABLE_WAYLAND="y"
  fi

  ENABLE_BROWSER="$(ask_yes_no "Induljon automatikusan a Chromium kioszk módban?" "y")"
  if is_yes "$ENABLE_BROWSER"; then
    if ! is_yes "$ENABLE_CHROMIUM"; then
      warn "A kioszk-autostart Chromiumot igényel; a Chromium telepítése automatikusan bekapcsolva."
      ENABLE_CHROMIUM="y"
    fi
    WORK_URL="$(ask_value "Kezelőpanel URL" "http://192.168.1.40:18006")"
    validate_http_url "$WORK_URL" || die "Érvénytelen kezelőpanel URL: $WORK_URL"

    ENABLE_INCOGNITO="$(ask_yes_no "Induljon a Chromium inkognitó módban?" "n")"
    ENABLE_NET_WAIT="$(ask_yes_no "Várjon hálózatra a Chromium indulás előtt?" "y")"
    if is_yes "$ENABLE_NET_WAIT"; then
      PING_HOST="$(ask_value "Hálózati ellenőrzés célpontja" "$(url_host "$WORK_URL")")"
      validate_host "$PING_HOST" || die "Érvénytelen hálózati célpont: $PING_HOST"
      NETWORK_WAIT_SECONDS="$(ask_positive_integer "Maximális hálózati várakozás másodpercben" "30")"
    fi

    ENABLE_IDLE="$(ask_yes_no "Kapcsoljuk be az inaktív KIOSK képernyőt?" "y")"
    if is_yes "$ENABLE_IDLE"; then
      IDLE_URL="$(ask_value "Inaktív KIOSK URL" "https://kiosk.athq.cc")"
      validate_http_url "$IDLE_URL" || die "Érvénytelen inaktív KIOSK URL: $IDLE_URL"
      IDLE_TIMEOUT="$(ask_positive_integer "Hány másodperc inaktivitás után váltson KIOSK nézetre?" "20")"
    fi
  else
    ENABLE_IDLE="n"
    ENABLE_NET_WAIT="n"
  fi

  ENABLE_CURSOR_HIDE="$(ask_yes_no "Rejtsük el automatikusan az egérkurzort induláskor?" "y")"
  ENABLE_WALLPAPER="$(ask_yes_no "Telepítsük az előre definiált Alu-Technika hátteret?" "y")"
  ENABLE_SPLASH="$(ask_yes_no "Telepítsük a saját, csomagfrissítéstől független Plymouth splash témát?" "y")"

  FORCE_RESOLUTION="$(ask_yes_no "Kényszerítsük a kijelzőt 1920x1080@60 módra?" "y")"
  if is_yes "$FORCE_RESOLUTION"; then
    DISPLAY_OUTPUT="$(ask_value "Wayland/DRM kijelző neve" "$(detect_display_output)")"
    DISPLAY_MODE="$(ask_value "Kijelzőmód" "1920x1080@60")"
    validate_display_name "$DISPLAY_OUTPUT" || die "Érvénytelen kijelzőnév: $DISPLAY_OUTPUT"
    validate_display_mode "$DISPLAY_MODE" || die "Érvénytelen kijelzőmód: $DISPLAY_MODE"
  fi

  ENABLE_ROTATION="$(ask_yes_no "Szükséges a kijelző elforgatása?" "n")"
  if is_yes "$ENABLE_ROTATION"; then
    DISPLAY_TRANSFORM="$(ask_choice "Kijelző tájolása" "normal" "90" "180" "270")"
  fi

  ENABLE_HDMI_AUDIO="$(ask_yes_no "Tiltsuk le az analóg hangot, hogy a HDMI legyen az elsődleges?" "y")"
  ENABLE_CEC="$(ask_yes_no "Engedélyezzük a HDMI-CEC távirányító támogatást?" "n")"

  ENABLE_NETWATCH="$(ask_yes_no "Engedélyezzük az internet + Chromium renderer KIOSK watchdogot és a korlátozott persistent hibajournalt?" "y")"
  if is_yes "$ENABLE_NETWATCH"; then
    NETWATCH_REBOOT_MINUTES="$(ask_positive_integer "Hány perc folyamatos teljes internetkimaradás után induljon újra?" "20")"
  fi

  # A böngésző, a labwc kurzorkezelés, a swaybg és a wlr-randr mind Waylandot
  # igényel. Ne engedjünk olyan kombinációt, amely telepítés után biztosan hibás.
  if ! is_yes "$ENABLE_WAYLAND"; then
    if is_yes "$ENABLE_BROWSER" || \
      is_yes "$ENABLE_CURSOR_HIDE" || \
      is_yes "$ENABLE_WALLPAPER" || \
      is_yes "$FORCE_RESOLUTION" || \
      is_yes "$ENABLE_ROTATION"; then
      warn "A kiválasztott KIOSK funkciók Wayland/labwc környezetet igényelnek; a Wayland modul automatikusan bekapcsolva."
      ENABLE_WAYLAND="y"
    fi
  fi
}

show_plan() {
  section "Összegzés"
  print_choice "APT csomaglista frissítés" "$ASK_APT_UPDATE"
  print_choice "Telepített csomagok frissítése" "$ASK_APT_UPGRADE"
  print_choice "labwc / Wayland" "$ENABLE_WAYLAND"
  print_choice "Chromium" "$ENABLE_CHROMIUM"
  print_choice "greetd autologin" "$ENABLE_GREETD"
  print_choice "Chromium kioszk autostart" "$ENABLE_BROWSER"
  if is_yes "$ENABLE_BROWSER"; then
    info "Kezelőpanel: $WORK_URL"
    print_choice "Inaktív KIOSK nézet" "$ENABLE_IDLE"
    if is_yes "$ENABLE_IDLE"; then
      info "Inaktív oldal: $IDLE_URL (${IDLE_TIMEOUT} mp)"
    fi
  fi
  print_choice "Kurzor automatikus elrejtése" "$ENABLE_CURSOR_HIDE"
  print_choice "Alu-Technika háttér" "$ENABLE_WALLPAPER"
  print_choice "Saját Plymouth splash téma" "$ENABLE_SPLASH"
  print_choice "1080p kijelzőmód" "$FORCE_RESOLUTION"
  print_choice "HDMI-hang elsődlegessé tétele" "$ENABLE_HDMI_AUDIO"
  print_choice "HDMI-CEC" "$ENABLE_CEC"
  print_choice "Internet + Chromium KIOSK watchdog" "$ENABLE_NETWATCH"
}

apply_configuration() {
  acquire_sudo
  apply_package_changes
  prepare_managed_directories

  apply_session_module
  apply_browser_module
  apply_appearance_module
  apply_hardware_module
  apply_netwatch_module
  apply_labwc_autostart

  verify_installation
  rm -f -- "$HOME_DIR/rpi-kiosk-install-error.log"
}

main() {
  init_runtime
  banner
  preflight
  collect_configuration
  show_plan

  if ! is_yes "$(ask_yes_no "Alkalmazzuk ezeket a beállításokat?" "y")"; then
    info "A telepítés módosítás nélkül megszakítva."
    return 0
  fi

  apply_configuration

  section "Kész"
  success "A kioszk telepítése és ellenőrzése sikeresen befejeződött."
  info "A telepítő forrásai a TEMP könyvtárral együtt automatikusan törlődnek."
  info "A tartós fájlok kizárólag az /etc/rpi-kiosk, /usr/local és a labwc konfiguráció kezelt részei."

  if is_yes "$(ask_yes_no "Indítsuk újra most a Raspberry Pi-t?" "y")"; then
    success "Újraindítás..."
    sudo systemctl reboot
  else
    warn "A grafikus és boot-beállítások érvényesítéséhez indítsd újra később a gépet."
  fi
}

main "$@"
