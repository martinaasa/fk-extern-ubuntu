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

## Konservativ Citrix-konfiguration

Scriptet ändrar inte Citrix SmartCard-konfiguration som standard.

Det var ett medvetet val. Citrix/FK-paketets standardkonfiguration bör lämnas orörd om den fungerar. Scriptet installerar nödvändiga paket och beroenden, men skriver inte om `module.ini`, `AuthManConfig.xml`, `scardConfig.json` eller `usb.conf` utan explicit felsökningsflagga.

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
