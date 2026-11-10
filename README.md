# FK Extern Ubuntu helper

Inofficiella, vibe-kodade hjälpscript för installation av FK Extern-komponenter på Ubuntu.

## Viktigt

Detta är **inte** en officiell eller supportad installation.

Detta är **vibe-kodat** och bygger på praktisk felsökning i en specifik miljö. Scriptet kan innehålla fel, antaganden och miljöberoenden.

Jag ger **ingen support** på scriptet.

Använd bara scriptet om du själv kan läsa och förstå vad det gör.

## Scope

Scriptet hanterar installation av FK Extern-komponenter på Ubuntu:

- `pcscd`
- `pcsc-tools`
- `libccid`
- `libnss3-tools`
- `libpcsclite-dev`
- Citrix Workspace App från FK:s Ubuntu-paket
- Citrix USB-stöd från FK:s Ubuntu-paket
- PointSharp Net iD Client från FK:s Ubuntu-paket
- registrering av Net iD PKCS#11-modul i Firefox
- grundläggande kontroll av kortläsare
- användaranpassning av Citrix för mittenklick och vanliga kortkommandon
- avstängning av Citrix autentiseringsspårning för att förebygga skenande loggfiler

Scriptet hanterar inte installation eller migrering av Firefox. För det finns separat repo:

```text
https://github.com/martinaasa/ubuntu-firefox-deb-migration
```

## Krav: icke-sandboxad Firefox

FK Extern med Net iD kräver en icke-sandboxad Firefox-installation som kan ladda Net iD:s PKCS#11-modul från värdsystemet:

```text
/lib/netid/libnetid.so
```

Snap- och Flatpak-versioner av Firefox stöds därför inte av detta script. Firefox ska vara installerad som riktig `.deb`.

## Installation

```bash
git clone <repo-url>
cd fkextern-ubuntu-helper
chmod +x scripts/install-fkextern.sh
./scripts/install-fkextern.sh
```

Scriptet visar en preflight-sammanfattning innan det gör ändringar.

Kör utan prompt:

```bash
./scripts/install-fkextern.sh --yes
```

## Viktigt efter installation

Starta om datorn efter installationen innan du testar Citrix/remote desktop.

Detta är inte bara ett allmänt tips. Utan omstart kan gamla `pcscd`-, Net iD- eller Citrix-processer ligga kvar i fel läge. Symptom kan vara att Citrix-sessionen startar men att smartkortet rapporteras som tomt, eller att PIN-flödet inte kommer igång.

Installationsscriptet skapar markören:

```text
/tmp/fkextern-reboot-required
```

Diagnos-scriptet varnar om denna finns kvar.

## FK Extern-paket

Scriptet hämtar FK Extern-paketet från FK:s publika nedladdningsyta:

```text
https://download.forsakringskassan.se/FK/Linux/
```

Standardpaketet i scriptet är:

```text
FKextern2605_ubuntu_PoC
```

Förväntade filer:

```text
icaclient_26.01.0.150_amd64.deb
ctxusb_26.01.0.150_amd64.deb
netidsetup_v1.3.4.10_linux_fk-001.tar.gz
```

Om paketet saknas är den troligaste orsaken att FK har publicerat en nyare version. Då behöver scriptet uppdateras med aktuellt paketnamn och aktuella filnamn.

## Vanliga flaggor

```bash
./scripts/install-fkextern.sh --help
./scripts/install-fkextern.sh --dry-run
./scripts/install-fkextern.sh --no-reset
./scripts/install-fkextern.sh --force-download
./scripts/install-fkextern.sh --media-dir /path/to/ubuntu_extern2605
./scripts/install-fkextern.sh --skip-card-reader-check
./scripts/install-fkextern.sh --force-unsupported-os
```

## Citrix: mus och vanliga kortkommandon

Installationsscriptet uppdaterar användarens `~/.ICAClient/wfclient.ini` med:

```ini
[WFClient]
MouseSendsControlV=False
WCAGModeKeyCombination=
TransparentKeyPassthrough=Remote
UseCtrlAltEnd=True
KeyPassthroughEscapeChar=Pause
KeyPassthroughEscapeShift=Alt+Ctrl+Shift
RelativeMouseOnChar=Pause
RelativeMouseOnShift=Alt+Shift
RelativeMouseOffChar=Pause
RelativeMouseOffShift=Alt+Shift
```

`MouseSendsControlV=False` gör att musens mittenknapp skickas som ett vanligt mittenklick till Citrix-sessionen. Det gör bland annat att mittenklick på en länk i webbläsaren kan öppna länken i en ny flik, i stället för att Citrix översätter klicket till `Ctrl+V`.

Scriptet sätter också `Hotkey1Char` till och med `Hotkey12Char` till `(none)`. Detta stänger av Citrix översättning av `Ctrl+Shift+F1–F12` till `Alt+F1–F12`. Modifierarinställningarna lämnas kvar; att bara ta bort modifierarna kan i stället fånga vanliga funktionstangenter.

| Genväg | Citrix beteende före anpassningen | Automatisk anpassning |
| --- | --- | --- |
| `Ctrl+Shift+T` | Öppnar Desktop Viewers verktygsfält. | Verktygsfältsbindningen stängs av så webbläsaren kan återöppna en stängd flik. |
| `Ctrl+Shift+F1–F12` | Kan översättas till `Alt+F1–F12` i översatt tangentbordsläge. | De tolv översättningarna stängs av via `Hotkey1Char`–`Hotkey12Char`. |
| `Ctrl+F2` | Släpper tangentbordsfångsten; kan också växla helskärm om den funktionen aktiverats. | Citrix-genvägen flyttas till `Ctrl+Alt+Shift+Pause`. |
| `Ctrl+Alt+Enter` | Skickar normalt `Ctrl+Alt+Delete` till fjärrsessionen. | Den funktionen flyttas till `Ctrl+Alt+End`. |
| `Ctrl+F12` / `Ctrl+Shift+F12` | Styr relativ mus när den funktionen är aktiverad. | Relativ mus växlas med `Alt+Shift+Pause`; musläget i sig bevaras. |
| `Alt+Tab` och Windows-genvägar | Skickas normalt till lokal dator i fönsterläge. | `TransparentKeyPassthrough=Remote` begär att de går till fjärrsessionen även i fönsterläge. |

`Ctrl+Alt+Shift+Pause` ger en separat väg tillbaka till lokala program. Verktygsfältets musknappar kan också användas för att minimera sessionen eller lämna helskärm om tangentbordet saknar Pause. Lokala skrivbordsgenvägar och Wayland kan fortfarande ha företräde framför Citrix; denna anpassning ändrar Citrix inställningar.

Inställningarna sätts automatiskt efter Citrix-installationen, även när Citrix redan är installerat och efter `--reset-user-citrix-cache`. Saknas `wfclient.ini` skapas den från Citrix installerade mall.

Övriga inställningar och filens behörigheter bevaras. Filen säkerhetskopieras till `wfclient.ini.bak.<tidsstämpel>` om den behöver ändras. Om rätt inställningar redan finns lämnas filen orörd och ingen ny backup skapas. En pågående Citrix-session behöver återanslutas för att läsa in ändringen.

Källor: [Citrix tangentbordsinställningar](https://docs.citrix.com/us/en/citrix-workspace-app-for-linux/devices/keyboard.html), [felsökning av kortkommandon](https://docs.citrix.com/us/en/citrix-workspace-app-for-linux/troubleshooting.html#keyboard-shortcuts), [Linux OEM-referens](https://github.com/citrix/workspace-linux-oem-guide/blob/master/docs/reference-information.md), [verktygsfältsgenväg](https://docs.citrix.com/us/en/citrix-workspace-app-for-linux/store-configuration.html#modify-or-disable-a-keyboard-shortcut-combinations) och [relativ mus i Linux-guiden](https://docs.citrix.com/en-us/citrix-workspace-app-for-linux/downloads/citrix-workspace-app-for-linux-2311.pdf).

Konfigurationsdelen kan testas utan att installera paket eller ändra användarens riktiga Citrix-konfiguration:

```bash
python3 -B -m unittest discover -s tests -v
```

## Konservativ Citrix-konfiguration

Scriptet sätter `TracingEnabled=false` i `/opt/Citrix/ICAClient/config/AuthManConfig.xml` efter installationen av Citrix och Net iD. På en drabbad installation skrev autentiseringstjänstens smartkortsövervakning omkring 15 GiB loggtext per timme med spårningen påslagen, trots `LoggingMode=normal`.

Endast spårningsflaggan ändras, med backup vid behov. Kortinloggning, PKCS#11-modul, kortläsarövervakning och övriga autentiseringsinställningar bevaras. Om spårningen redan är avstängd lämnas filen orörd. Inställningen läses när autentiseringstjänsten startas, alltså vid den omstart som redan krävs efter installationen. Se [Citrix dokumentation om spårning och loggar](https://docs.citrix.com/us/en/citrix-workspace-app-for-linux/troubleshooting.html).

Användarinställningarna för mus och tangentbord beskrivs ovan. Ändringar i `module.ini`, `scardConfig.json` och `usb.conf` kräver fortfarande explicit felsökningsflagga.

Felsökningsflaggor finns, men bör inte användas normalt:

```bash
./scripts/install-fkextern.sh --reset-user-citrix-cache
./scripts/install-fkextern.sh --configure-citrix-smartcard
./scripts/install-fkextern.sh --set-citrix-pcsclibrary-full-path
./scripts/install-fkextern.sh --disable-citrix-usb-smartcard
```

## Diagnostik

Diagnostikscriptet ändrar inget på systemet. Det samlar status för Firefox, Net iD, Citrix och kortläsare.

```bash
chmod +x scripts/diagnose-fkextern.sh
./scripts/diagnose-fkextern.sh
```

Loggen skrivs till:

```text
/tmp/fkextern-diagnose.log
```

Diagnosen letar bland annat efter:

```text
libpcsclite.so saknas
wfica segfault
gamla adapter-processer
defunct icasessionmgr
Failed to cache VDA certificate
No PIN acquired
Session launch readiness achieved
Inserting new Reader
```

## Known good i Citrix-loggen

Ett fungerande Citrix-flöde kan fortfarande innehålla rader som ser störiga ut, till exempel:

```text
Failed to cache VDA certificate
ReadOneLine: no line 76
OpenGL rendering enabled
```

De är inte nödvändigtvis blockerande.

Viktigare tecken på att sessionen faktiskt fungerar är:

```text
Succeed in launch session
ncsConnected
Session launch readiness achieved
ModuleLoad: /opt/Citrix/ICAClient/VDSCARDV2.DLL
Inserting new Reader
```

Om sessionen startar men remote desktop säger att smartkortet är tomt, och loggen visar `No PIN acquired`, starta om datorn om installationen nyss körts.

## libpcsclite-dev

Citrix kan försöka ladda osuffixade:

```text
libpcsclite.so
```

På Ubuntu kommer denna normalt från:

```text
libpcsclite-dev
```

Därför installerar scriptet `libpcsclite-dev` även om det kan kännas som ett utvecklingspaket.

## Avgränsning och ansvar

Scriptet kör systemändringar med `sudo`, installerar paket och kan rensa tidigare Citrix/Net iD-installationer.

Läs igenom scriptet innan användning.

Detta är vibe-kodat och osupportat. Användaren ansvarar själv för att förstå vad scriptet gör, ha en fungerande backup/återställningsväg och kunna felsöka sin egen arbetsmiljö.

Jag ger ingen support på scriptet.
