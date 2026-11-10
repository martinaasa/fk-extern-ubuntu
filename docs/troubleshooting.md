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

## Andra kortkommandon fångas av Citrix

Installationsscriptet frigör även `Ctrl+Shift+F1–F12`, `Ctrl+F2` och `Ctrl+Alt+Enter`. När relativ mus används flyttas också dess `Ctrl+F12`- och `Ctrl+Shift+F12`-bindningar. Inställningarna och källorna finns i README under **Citrix: mus och vanliga kortkommandon**.

Efter anpassningen används följande Citrix-genvägar:

- `Ctrl+Alt+Shift+Pause`: släpp tangentbordsfångsten för lokala program; används också för helskärmsväxling om den funktionen är aktiverad.
- `Ctrl+Alt+End`: skicka `Ctrl+Alt+Delete` till fjärrsessionen.
- `Alt+Shift+Pause`: växla relativ mus när den funktionen är aktiverad.

Verktygsfältets musknappar kan användas för att minimera sessionen eller lämna helskärm om tangentbordet saknar Pause.

För `Alt+Tab` och Windows-genvägar sätter scriptet `TransparentKeyPassthrough=Remote`, så att Citrix begär dem även i fönsterläge. Om de ändå går till den lokala datorn, kontrollera lokala Ubuntu-genvägar och om sessionen körs under Wayland. Sådana reservationer kan ha företräde framför Citrix.

Koppla från och återanslut Citrix-sessionen efter ändringar i konfigurationen.

## AuthManSvr-loggen växer snabbt

Filerna `~/.ICAClient/logs/AuthManSvr-*.log` kan bli mycket stora när `TracingEnabled=true` är påslaget i `/opt/Citrix/ICAClient/config/AuthManConfig.xml`. `LoggingMode=normal` stänger inte av den separata funktionsspårningen. Kontrollera flaggan med:

```bash
grep -A1 '<key>TracingEnabled</key>' /opt/Citrix/ICAClient/config/AuthManConfig.xml
```

Installationsscriptet sätter automatiskt `TracingEnabled=false`, med backup. Nästa start av autentiseringstjänsten läser in ändringen. Inga kortinloggningsinställningar ändras för detta.

Kontrollera separat om `AuthManagerDaemon` använder mycket CPU även när loggskrivningen har stoppat. Det kan vara ett ytterligare fel i kortläsarövervakningen; en stängd loggflod bevisar inte att CPU-problemet är löst.

Spara ett begränsat felsökningsutdrag före rensning av en stor logg. Kontrollera vilka processer som håller filen öppen. Om en backup läser filen kan den behålla diskutrymmet efter borttagning tills läsningen stängs. På komprimerande filsystem kan loggens textstorlek vara mycket större än det faktiskt allokerade utrymmet.

## Rensa användarens Citrix-cache

```bash
./scripts/install-fkextern.sh --reset-user-citrix-cache
```

Detta flyttar undan `~/.ICAClient` till en backup-katalog. Efter Citrix-installationen skapas användarkonfigurationen på nytt med `Ctrl+Shift+T` frigjort för fjärrsessionen.
