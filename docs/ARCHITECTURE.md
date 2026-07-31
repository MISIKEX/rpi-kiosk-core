# Telepítőarchitektúra

## Tervezési célok

1. Egyetlen, TEMP-be klónozható belépési pont.
2. Gyors telepítés: a csomagok egy összevont APT-lépésben kerülnek fel.
3. Biztonságos újrafuttatás: saját fájlok és megjelölt blokkok felülírása.
4. Valódi hibakezelés: minden háttérfolyamat kilépési kódja ellenőrzött.
5. Moduláris bővíthetőség.
6. A kezelőpanel és az inaktív KIOSK nézet gyors, sorosított váltása.
7. A Raspberry Pi OS saját kijelzőblankolásának kikapcsolása, hogy az idle oldal folyamatosan látható maradjon.

## Könyvtárak

```text
kiosk_setup.sh            Interaktív vezérlő és telepítési sorrend
lib/core.sh               Naplózás, kérdések, validáció, fájlműveletek
modules/packages.sh       APT-csomagok
modules/session.sh        labwc, seatd, greetd/LightDM
modules/browser.sh        Chromium-konfiguráció és policy
modules/appearance.sh     háttér, splash, kurzor, labwc autostart
modules/hardware.sh       bootparaméterek, kijelző, hang, CEC
modules/netwatch.sh       internet-watchdog
templates/                telepített futó fájlok és systemd egységek
tests/test.sh             helyi statikus és funkcionális ellenőrzés
```

## Telepítési életciklus

```text
preflight
  → összes válasz begyűjtése
  → URL- és értékvalidálás
  → terv megjelenítése
  → felhasználói jóváhagyás
  → egyesített csomagtelepítés
  → modulok alkalmazása
  → systemd- és fájlellenőrzés
  → opcionális reboot
```

Rendszermódosítás nem történik addig, amíg az összes kérdésre nincs érvényes válasz, és a felhasználó nem hagyta jóvá az összegzést.

## Kezelt konfigurációk

A megosztott konfigurációs fájlokban a telepítő ezt a blokkot használja:

```text
# RPI_KIOSK_MANAGED_BEGIN
...
# RPI_KIOSK_MANAGED_END
```

Újrafuttatáskor a teljes korábbi blokk törlődik, majd az új állapot egyszer kerül be. A régi `KIOSKPARANCS` blokkokat a migráció automatikusan eltávolítja.

A teljesen saját fájlok `rpi-kiosk-*` néven kerülnek telepítésre, ezért pontosan azonosíthatók és biztonságosan frissíthetők.

A böngészővezérlő külön work és idle profilt használ. Váltáskor az új nézet
előbb elindul, majd a korábbi, PID-del azonosított folyamat szabályosan leáll.
A művelet `flock` zárolást használ, így az egymásra futó idle/resume események
sorban hajtódnak végre.

## Új modul hozzáadása

Egy új modul:

1. a `modules/` könyvtárban kapjon külön fájlt;
2. csak a saját, `rpi-kiosk-*` nevű fájljait kezelje;
3. legyen engedélyezési és kikapcsolási útvonala;
4. újrafuttatáskor ne készítsen második konfigurációt vagy szolgáltatást;
5. az alkalmazás után ellenőrizze a létrehozott fájlokat/szolgáltatásokat;
6. a szükséges csomagokat a `build_package_list` függvényhez adja hozzá;
7. kapjon szintaktikai vagy funkcionális tesztet.
