# Telepítőarchitektúra

## Tervezési célok

1. Egyetlen, TEMP-be klónozható belépési pont.
2. Gyors telepítés: a csomagok egy összevont APT-lépésben kerülnek fel.
3. Biztonságos újrafuttatás: saját fájlok és megjelölt blokkok felülírása.
4. Valódi hibakezelés: minden háttérfolyamat kilépési kódja ellenőrzött.
5. Moduláris bővíthetőség.
6. A kezelőpanel és az inaktív KIOSK nézet gyors, sorosított váltása.
7. A Raspberry Pi OS saját kijelzőblankolásának kikapcsolása, hogy az idle oldal folyamatosan látható maradjon.
8. Chromium renderer-szintű állapotfigyelés és fokozatos önhelyreállítás.
9. Saját Plymouth téma és korlátozott persistent journal használata, csomagfrissítéstől és reboottól független diagnosztikával.
10. Hibás funkciókombinációk automatikus normalizálása, például Waylandot igénylő KIOSK funkciók esetén a labwc/Wayland modul bekapcsolása.

## Könyvtárak

```text
kiosk_setup.sh                         Interaktív vezérlő és telepítési sorrend
lib/core.sh                            Naplózás, kérdések, validáció, fájlműveletek
modules/packages.sh                    APT-csomagok és függőségek
modules/session.sh                     labwc, seatd, greetd/LightDM
modules/browser.sh                     Chromium-konfiguráció és policy
modules/appearance.sh                  háttér, splash, kurzor, labwc autostart
modules/hardware.sh                    bootparaméterek, kijelző, hang, CEC
modules/netwatch.sh                    internet + Chromium renderer watchdog és journal
templates/rpi-kiosk-browser            work/idle Chromium folyamatvezérlő
templates/rpi-kiosk-netwatch           futó watchdog
templates/rpi-kiosk-chromium-health.py renderer JavaScript health-check
templates/journald/                    korlátozott persistent journal
templates/plymouth/                    saját rpi-kiosk Plymouth téma
templates/systemd/                     kezelt systemd egységek
tests/test.sh                          statikus, higiéniai és funkcionális ellenőrzés
```

## Telepítési életciklus

```text
preflight
  → összes válasz begyűjtése
  → URL- és értékvalidálás
  → függő opciók normalizálása
  → terv megjelenítése
  → felhasználói jóváhagyás
  → egyesített csomagtelepítés
  → modulok alkalmazása
  → systemd- és fájlellenőrzés
  → opcionális reboot
```

Rendszermódosítás nem történik addig, amíg az összes kérdésre nincs érvényes válasz, a függőségek nincsenek konzisztens állapotban, és a felhasználó nem hagyta jóvá az összegzést.

## Kezelt konfigurációk

A megosztott konfigurációs fájlokban a telepítő ezt a blokkot használja:

```text
# RPI_KIOSK_MANAGED_BEGIN
...
# RPI_KIOSK_MANAGED_END
```

Újrafuttatáskor a teljes korábbi blokk törlődik, majd az új állapot egyszer kerül be. A régi `KIOSKPARANCS` blokkokat és a korábbi KIOSK szolgáltatás-/fájlneveket a migráció célzottan eltávolítja.

A teljesen saját fájlok `rpi-kiosk-*` néven kerülnek telepítésre, ezért pontosan azonosíthatók és biztonságosan frissíthetők. A migrációs kód kizárólag a már telepített régi gépek kompatibilitása miatt marad a core-ban; külső vagy korábbi GitHub repositoryt nem használ.

## Chromium folyamatmodell

A böngészővezérlő külön work és idle profilt használ. Váltáskor az új nézet előbb elindul, majd a korábbi, PID-del azonosított folyamat szabályosan leáll. A művelet `flock` zárolást használ, így az egymásra futó idle/resume események sorban hajtódnak végre.

A work és idle Chromium külön, kizárólag localhoston figyelő DevTools portot használ. A watchdog a DevTools WebSocketen JavaScriptet futtat a rendererben, ezért egy élő, de befagyott Chromium processzt is meg tud különböztetni egy valóban válaszoló böngészőtől.

A helyreállítás fokozatos: ismételt renderer-hiba esetén először csak Chromium `force-restart` történik; teljes rendszer-reboot csak többszöri sikertelen böngésző-helyreállítás vagy tartós teljes internetkimaradás után következik.

## Diagnosztika és boot

A KIOSK watchdog bekapcsolásakor a telepítő saját journald drop-int használ, legfeljebb 64 MB és 7 nap megőrzéssel. Ez lehetővé teszi az előző boot vizsgálatát anélkül, hogy korlátlan naplónövekedést engedne.

A splash saját `/usr/share/plymouth/themes/rpi-kiosk/` témába kerül. A Raspberry Pi OS `pix` témájának csomag által kezelt fájljait nem írjuk felül, ezért egy rendszerfrissítés nem cseréli vissza az egyedi képet.

## Új modul hozzáadása

Egy új modul:

1. a `modules/` könyvtárban kapjon külön fájlt;
2. csak a saját, `rpi-kiosk-*` nevű fájljait kezelje;
3. legyen engedélyezési és kikapcsolási útvonala;
4. újrafuttatáskor ne készítsen második konfigurációt vagy szolgáltatást;
5. az alkalmazás után ellenőrizze a létrehozott fájlokat/szolgáltatásokat;
6. a szükséges csomagokat a `build_package_list` függvényhez adja hozzá;
7. kapjon szintaktikai vagy funkcionális tesztet;
8. ne vezessen be külső, korábbi KIOSK repositoryra mutató futásidejű függőséget.
