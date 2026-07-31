#!/usr/bin/env bash

package_available() {
  apt-cache show "$1" >/dev/null 2>&1
}

build_package_list() {
  local requested=()
  local package_name

  if is_yes "$ENABLE_WAYLAND"; then
    requested+=(labwc wlr-randr seatd)
  fi
  if is_yes "$ENABLE_CHROMIUM" || is_yes "$ENABLE_BROWSER"; then
    requested+=(chromium)
  fi
  if is_yes "$ENABLE_IDLE"; then
    requested+=(swayidle)
  fi
  if is_yes "$ENABLE_WALLPAPER"; then
    requested+=(swaybg)
  fi
  if is_yes "$ENABLE_CURSOR_HIDE"; then
    requested+=(wtype python3)
  fi
  if is_yes "$ENABLE_SPLASH"; then
    requested+=(plymouth plymouth-themes initramfs-tools)
  fi
  if is_yes "$ENABLE_CEC"; then
    requested+=(ir-keytable v4l-utils)
  fi
  if is_yes "$ENABLE_NETWATCH" || is_yes "$ENABLE_NET_WAIT"; then
    requested+=(iputils-ping curl)
  fi
  if is_yes "$ENABLE_GREETD"; then
    requested+=(greetd dbus-user-session)
  fi
  requested+=(util-linux)

  declare -g -a INSTALL_PACKAGES=()
  declare -A seen=()
  for package_name in "${requested[@]}"; do
    [[ -n "${seen[$package_name]:-}" ]] && continue
    seen["$package_name"]=1
    if package_available "$package_name"; then
      INSTALL_PACKAGES+=("$package_name")
    else
      die "A szükséges '$package_name' csomag nem érhető el az APT-forrásokban."
    fi
  done
}

apply_package_changes() {
  section "Csomagkezelés"

  if is_yes "$ASK_APT_UPDATE"; then
    run_step "APT csomaglista frissítése" sudo apt-get update
  fi

  if is_yes "$ASK_APT_UPGRADE"; then
    run_step "Telepített csomagok frissítése" \
      sudo env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  fi

  build_package_list
  if ((${#INSTALL_PACKAGES[@]})); then
    run_step "Szükséges csomagok telepítése" \
      sudo env DEBIAN_FRONTEND=noninteractive apt-get install \
      --no-install-recommends -y "${INSTALL_PACKAGES[@]}"
  fi

  success "A csomagkezelési lépések befejeződtek."
}
