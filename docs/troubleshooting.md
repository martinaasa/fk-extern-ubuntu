# Troubleshooting

## Firefox failar i install-scriptet

Scriptet kräver riktig Firefox `.deb`.

Snap- och Flatpak-Firefox stöds inte för FK Extern/NetiD eftersom Firefox behöver kunna ladda:

```text
/lib/netid/libnetid.so
```

Installera/migrera Firefox med:

```text
https://github.com/martinaasa/ubuntu-firefox-deb-migration
```

## FK-paketet hittas inte

Om scriptet säger att FK-paketet inte hittas på:

```text
https://download.forsakringskassan.se/FK/Linux/
```

är det troligaste att FK har publicerat en nyare version. Uppdatera:

- `FKEXTERN_VERSION`
- `FKEXTERN_PACKAGE_BASENAME`
- `CITRIX_CLIENT_DEB`
- `CITRIX_USB_DEB`
- `NETID_ARCHIVE`

## Net iD syns inte i Firefox

Kör:

```bash
./scripts/diagnose-fkextern.sh
```

Kontrollera att:

- Firefox kör från `/usr/lib/firefox`, inte `/snap` eller `/app`
- `/lib/netid/libnetid.so` finns
- `modutil` visar `Net iD` i Firefox-profilen

## Kortläsaren hittas inte

Kontrollera:

```bash
systemctl status pcscd --no-pager
pcsc_scan
```

Sätt i kortläsaren igen och kör om:

```bash
sudo systemctl restart pcscd
pcsc_scan
```

## Citrix-frågor under installation

Om Citrix-installationen frågar om:

- AppProtection
- DeviceTrust
- EPAClient

välj `no`, enligt FK:s instruktion.
