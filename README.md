# Raspberry Pi KIOSK – Alu-Technika Kft.

Gyorsan telepíthető és biztonságosan újrafuttatható kioszkrendszer Raspberry Pi 4 gépekhez.

## Támogatott célrendszer

- Raspberry Pi 4
- Raspberry Pi OS / Debian 13 (Trixie), Desktop
- Wayland és labwc
- 1920×1080-as HDMI-monitor

## Gyors telepítés

A telepítő ideiglenes könyvtárba klónozza a projektet. A futás végén a teljes forráskönyvtár automatikusan törlődik:

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

Ugyanez a parancs később újra futtatható. A telepítő a saját fájljait és megjelölt konfigurációs blokkjait frissíti, nem készít duplikált bejegyzéseket.

## Működés

A normál, aktív nézet a helyi kezelőpanel. A `swayidle` figyeli a felhasználói aktivitást:

- egér- vagy billentyűaktivitáskor a kezelőpanel indul;
- az alapértelmezett 20 másodperces inaktivitás után az inaktív KIOSK oldal indul;
- az új nézet előbb megjelenik, és csak utána áll le a régi Chromium-folyamat;
- a két nézet külön böngészőprofilt használ, így a kezelőpanel állapota nem keveredik az inaktív oldallal;
- zárolás és PID-ellenőrzés akadályozza meg a párhuzamos vagy idegen Chromium-folyamatok leállítását.
- a Raspberry Pi OS saját képernyőblankolása letiltásra kerül, hogy az inaktív KIOSK oldal folyamatosan látható maradjon.

## Választható modulok

- APT csomaglista és rendszerfrissítés
- labwc / Wayland
- Chromium kioszk mód
- greetd autologin
- work/idle URL-váltás
- hálózatra várás
- egérkurzor elrejtése
- Alu-Technika háttérkép
- Alu-Technika Plymouth splash
- 1080p kijelzőmód és forgatás
- HDMI-hang
- HDMI-CEC távirányító
- internet-watchdog automatikus újraindítással

## Tartósan telepített elemek

A TEMP könyvtár törlődik. Csak a működéshez szükséges, név szerint kezelt elemek maradnak:

- `/etc/rpi-kiosk/` – kioszkbeállítások
- `/var/lib/rpi-kiosk/` – minimális állapot és visszaállítási információ
- `/usr/local/bin/rpi-kiosk-*` – futó segédprogramok
- `/usr/local/share/rpi-kiosk/` – telepített grafikai elemek
- `/etc/systemd/system/rpi-kiosk-*.service` – választható szolgáltatások
- `~/.config/labwc/` – megjelölt, duplikációmentes labwc-blokkok
- `~/.local/state/rpi-kiosk/chromium/` – elkülönített work/idle Chromium-profilok

Sikertelen telepítési lépésnél a hiba részletei a `~/rpi-kiosk-install-error.log` fájlba kerülnek. Sikeres telepítés nem hagy telepítési naplót.

## Fejlesztés és ellenőrzés

```bash
bash tests/test.sh
```

A teszt ellenőrzi a Bash-szintaxist, a kezelt blokkok ismételt frissítését, a bootparaméter-kezelő függvényeket és a hibakódok továbbadását.

Részletes felépítés: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
