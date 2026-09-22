# Raspberry Pi KIOSK – Alu-Technika Kft.

Gyorsan telepíthető és biztonságosan újrafuttatható kioszkrendszer Raspberry Pi 4 gépekhez.

Ez a repository a kioszkrendszer **egyetlen aktívan karbantartott forrása**.

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
- a két nézet külön böngészőprofilt és külön localhost DevTools portot használ;
- zárolás és PID-ellenőrzés akadályozza meg a párhuzamos vagy idegen Chromium-folyamatok leállítását;
- a Raspberry Pi OS saját képernyőblankolása letiltásra kerül, hogy az inaktív KIOSK oldal folyamatosan látható maradjon.

A telepítő a kiválasztott funkciók függőségeit konzisztensen kezeli: Waylandot igénylő KIOSK funkciók esetén a labwc/Wayland modul automatikusan bekapcsol, a renderer-watchdog Python futtatókörnyezete pedig explicit csomagfüggőség.

### KIOSK watchdog

A watchdog nem csak azt ellenőrzi, hogy van-e internetkapcsolat. A Chromium renderer állapotát is tényleges JavaScript-végrehajtással ellenőrzi a kizárólag `127.0.0.1` címre kötött DevTools porton.

Alapértelmezett működés:

- internetellenőrzés 30 másodpercenként;
- 20 perc folyamatos teljes internetkimaradás után rendszer-reboot;
- 3 egymást követő renderer-hiba után Chromium `force-restart`;
- 3 egymást követő sikertelen Chromium-helyreállítás után teljes rendszer-reboot;
- a systemd hardveres reboot-watchdog 30 másodperc után reseteli a Pi-t, ha a szabályos reboot a végső leállítási fázisban beragad;
- az aktuális work/idle URL elérhetőségének figyelése;
- ha egy korábban elérhetetlen kioszk URL visszatér, friss Chromium-helyreállítás történik.

A watchdoghoz korlátozott persistent journal tartozik. Ez maximum 64 MB rendszerjournalt és legfeljebb 7 napnyi diagnosztikai előzményt tart meg, így reboot után is visszanézhető, mi történt közvetlenül a hiba előtt.

### Plymouth splash

Az egyedi splash **nem** a Raspberry Pi OS `pix` témájának csomag által kezelt képét írja felül. Saját témát használ:

`/usr/share/plymouth/themes/rpi-kiosk/`

Így egy későbbi `rpd-plym-splash` vagy `pix-plym-splash` csomagfrissítés nem tudja felülírni az Alu-Technika splash képet.

## Választható modulok

- APT csomaglista és rendszerfrissítés
- labwc / Wayland
- Chromium kioszk mód
- greetd autologin
- work/idle URL-váltás
- hálózatra várás
- egérkurzor elrejtése
- Alu-Technika háttérkép
- saját Alu-Technika Plymouth splash téma
- 1080p kijelzőmód és forgatás
- HDMI-hang
- HDMI-CEC távirányító
- internet + Chromium renderer watchdog automatikus helyreállítással
- korlátozott persistent systemd journal

## Tartósan telepített elemek

A TEMP könyvtár törlődik. Csak a működéshez szükséges, név szerint kezelt elemek maradnak:

- `/etc/rpi-kiosk/` – kioszkbeállítások
- `/var/lib/rpi-kiosk/` – minimális állapot és visszaállítási információ
- `/usr/local/bin/rpi-kiosk-*` – futó segédprogramok
- `/usr/local/libexec/rpi-kiosk-chromium-health` – Chromium renderer health-check
- `/usr/local/share/rpi-kiosk/` – telepített grafikai elemek
- `/usr/share/plymouth/themes/rpi-kiosk/` – saját Plymouth téma
- `/etc/systemd/system/rpi-kiosk-*.service` – választható szolgáltatások
- `/etc/systemd/journald.conf.d/90-rpi-kiosk-persistent.conf` – korlátozott persistent diagnosztikai journal
- `/etc/systemd/system.conf.d/90-rpi-kiosk-watchdog.conf` – 1 perces runtime watchdog és 30 másodperces reboot-fallback
- `~/.config/labwc/` – megjelölt, duplikációmentes labwc-blokkok
- `~/.local/state/rpi-kiosk/chromium/` – elkülönített work/idle Chromium-profilok

Sikertelen telepítési lépésnél a hiba részletei a `~/rpi-kiosk-install-error.log` fájlba kerülnek. Sikeres telepítés nem hagy telepítési naplót.

## Fejlesztés és ellenőrzés

```bash
bash tests/test.sh
```

A teszt ellenőrzi a Bash-szintaxist, a Python health-check szintaxisát, a konfigurációvalidálást, a kezelt blokkok ismételt frissítését, a bootparaméter-kezelést, a work/idle Chromium-váltást, a külön localhost debug portokat és a `force-restart` működését. A repository-higiénia tesztje megakadályozza a korábbi, törölt KIOSK repók hivatkozásainak visszakerülését. A GitHub Actions CI minden push után automatikusan futtatja ezeket az ellenőrzéseket.

Részletes felépítés: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
