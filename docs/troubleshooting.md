# Troubleshooting

## Firefox failar i install-scriptet

Scriptet kräver riktig Firefox `.deb`. Snap- och Flatpak-Firefox stöds inte.

Se:

```text
https://github.com/martinaasa/ubuntu-firefox-deb-migration
```

## FK-paketet hittas inte

Om paketet saknas på `https://download.forsakringskassan.se/FK/Linux/` har FK sannolikt publicerat en nyare version. Uppdatera paketnamn och filnamn i installationsscriptet.

## Citrix fastnar på Connecting

Kör:

```bash
./scripts/diagnose-fkextern.sh
```

Kontrollera särskilt:

- om `wfica` kör
- om `icasessionmgr` är `<defunct>`
- om `libpcsclite.so` saknas
- om `wfica` segfaultar
- om `Session launch readiness achieved` finns i Citrix-loggen

## Sessionen startar men smartkortet verkar tomt

Kontrollera om Citrix-loggen innehåller:

```text
No PIN acquired
```

Om installationen nyss körts: starta om datorn.

## libpcsclite.so saknas

Fel i Citrix-loggen:

```text
host_DynamicLoad:load(libpcsclite.so: cannot open shared object file: No such file or directory)
```

Åtgärd:

```bash
sudo apt install libpcsclite-dev
sudo ldconfig
```

## Ctrl+Shift+T öppnar Citrix verktygsfält i stället för senaste stängda fliken

Installationsscriptet stänger automatiskt av Citrix bindning för `Ctrl+Shift+T`. Kontrollera att `~/.ICAClient/wfclient.ini` innehåller följande under `[WFClient]`:

```ini
WCAGModeKeyCombination=
```

Värdet efter `=` ska vara tomt. Koppla från och återanslut Citrix-sessionen, fokusera webbläsaren i fjärrsessionen och prova igen.

## Rensa användarens Citrix-cache

```bash
./scripts/install-fkextern.sh --reset-user-citrix-cache
```

Detta flyttar undan `~/.ICAClient` till en backup-katalog. Efter Citrix-installationen skapas användarkonfigurationen på nytt med `Ctrl+Shift+T` frigjort för fjärrsessionen.
