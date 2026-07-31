### 🖥️ Kiosk Mód Telepítése

Használd az alábbi parancsot a Kiosk mód automatikus telepítéséhez. A szkript egy ideiglenes könyvtárban dolgozik, így nem hagy szemetet a rendszerben:

```bash
tmpdir="$(mktemp -d)" && (
  set -e
  trap 'cd ~; rm -rf "$tmpdir"' EXIT

  echo "TEMP mappa: $tmpdir"
  git clone --depth 1 https://github.com/MISIKEX/rpi-kiosk-core.git "$tmpdir"
  cd "$tmpdir"

  chmod +x kiosk_idle_netwatch_setup.sh
  ./kiosk_idle_netwatch_setup.sh
)
```