# KIOSK mód telepítése

Normál felhasználóként futtasd az alábbi parancsot. A telepítő csak a szükséges műveleteknél kér `sudo` jogosultságot.

```bash
tmpdir="$(mktemp -d)" && (
  set -e
  trap 'cd ~; rm -rf "$tmpdir"' EXIT

  echo "TEMP mappa: $tmpdir"
  git clone --depth 1 https://github.com/MISIKEX/rpi-kiosk-core.git "$tmpdir"
  cd "$tmpdir"

  chmod +x kiosk_setup.sh
  ./kiosk_setup.sh
)
```

A források a futás végén automatikusan törlődnek. Módosítás vagy új modul beállítása esetén ugyanaz a parancs újra futtatható: a telepítő felülírja a saját fájljait, és lecseréli a korábban megjelölt konfigurációs blokkokat.

Az alapértelmezett célrendszer Raspberry Pi 4, Debian 13/Trixie Desktop, labwc/Wayland és 1920×1080-as HDMI-monitor.
