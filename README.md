# FK Extern Ubuntu helper

Inofficiellt hjälpscript för installation av FK Extern-komponenter på Ubuntu.

## Viktigt

Detta är **inte** en officiell eller supportad installation.

Jag ger **ingen support** på scriptet.

Scriptet är endast avsett för:

- anställda och konsulter på Försäkringskassan
- Ubuntu
- användare som redan har rätt att använda FK Extern
- FK Extern-paketet som publiceras av Försäkringskassan

Scriptet är inte avsett för:

- privatpersoner
- andra organisationer
- andra Linux-distributioner än Ubuntu
- generell Citrix-, NetiD-, smartcard- eller Firefox-support

Scriptet ger inte åtkomst till några tjänster. Åtkomst styrs fortfarande av behörighet, smartcard, certifikat, PIN och övriga FK Extern-förutsättningar.

## Scope

Scriptet hanterar installation av FK Extern-komponenter på Ubuntu:

- `pcscd`
- `pcsc-tools`
- `libccid`
- `libnss3-tools`
- Citrix Workspace App från FK:s Ubuntu-paket
- Citrix USB-stöd från FK:s Ubuntu-paket
- PointSharp Net iD Client från FK:s Ubuntu-paket
- registrering av Net iD PKCS#11-modul i Firefox
- grundläggande kontroll av kortläsare

Scriptet hanterar **inte**:

- installation av Firefox
- migrering från Snap/Flatpak-Firefox
- borttagning av gamla Firefox-installationer
- felsökning av personliga Firefox-inställningar
- support på NSGW, Citrix-miljöer eller FK:s externa tjänster

## Krav: icke-sandboxad Firefox

FK Extern med Net iD kräver en icke-sandboxad Firefox-installation som kan ladda Net iD:s PKCS#11-modul från värdsystemet:

```text
/lib/netid/libnetid.so
```

Snap- och Flatpak-versioner av Firefox stöds därför inte av detta script. De kan blockera åtkomst till systembibliotek via sandboxning, vilket gör att Net iD-modulen inte kan laddas korrekt.

Firefox ska vara installerad som riktig `.deb`.

För installation och migrering till Firefox `.deb`, se separat repo:

```text
https://github.com/martinaasa/ubuntu-firefox-deb-migration
```

Detta FK Extern-script installerar inte Firefox. Om Firefox inte är en riktig `.deb` failar scriptet och hänvisar till repot ovan.

## Stödda system

Scriptet är endast avsett för Ubuntu.

Andra Linux-distributioner stöds inte.

Om scriptet körs på en Ubuntu-version som inte är uttryckligen testad kommer det att varna eller avbryta, beroende på flaggor.

## FK Extern-paket

Scriptet hämtar FK Extern-paketet från FK:s publika nedladdningsyta:

```text
https://download.forsakringskassan.se/FK/Linux/
```

Standardpaketet i scriptet är:

```text
FKextern2605_ubuntu_PoC
```

Scriptet testar både:

```text
https://download.forsakringskassan.se/FK/Linux/FKextern2605_ubuntu_PoC
https://download.forsakringskassan.se/FK/Linux/FKextern2605_ubuntu_PoC.zip
```

Om paketet saknas är den troligaste orsaken att FK har publicerat en nyare version och ersatt den gamla. Då behöver scriptet uppdateras med aktuellt paketnamn och aktuella filnamn.

## Förväntade filer i FK-paketet

Scriptet förväntar sig följande filer i FK-paketet:

```text
icaclient_26.01.0.150_amd64.deb
ctxusb_26.01.0.150_amd64.deb
netidsetup_v1.3.4.10_linux_fk-001.tar.gz
```

Om FK publicerar ett nytt paket med andra versionsnummer behöver scriptet uppdateras.

## Installation

Klona repot och kör installationsscriptet:

```bash
git clone <repo-url>
cd fkextern-ubuntu-helper

chmod +x scripts/install-fkextern.sh
./scripts/install-fkextern.sh
```

Scriptet visar en preflight-sammanfattning innan det gör ändringar.

För att köra utan bekräftelseprompt:

```bash
./scripts/install-fkextern.sh --yes
```

## Vanliga flaggor

Visa hjälp:

```bash
./scripts/install-fkextern.sh --help
```

Testkör utan att göra ändringar:

```bash
./scripts/install-fkextern.sh --dry-run
```

Kör utan att rensa tidigare Citrix/NetiD-installation:

```bash
./scripts/install-fkextern.sh --no-reset
```

Använd lokalt uppackat FK-paket:

```bash
./scripts/install-fkextern.sh --media-dir /path/to/ubuntu_extern2605
```

Tvinga ny hämtning av FK-paketet:

```bash
./scripts/install-fkextern.sh --force-download
```

Hoppa över kortläsarkontroll:

```bash
./scripts/install-fkextern.sh --skip-card-reader-check
```

Kör på ej uttryckligen testad Ubuntu-version:

```bash
./scripts/install-fkextern.sh --force-unsupported-os
```

## Diagnostik

Diagnostikscriptet ändrar inget på systemet. Det samlar bara status för Firefox, Net iD, Citrix och kortläsare.

```bash
chmod +x scripts/diagnose-fkextern.sh
./scripts/diagnose-fkextern.sh
```

Loggen skrivs till:

```text
/tmp/fkextern-diagnose.log
```

## Loggar

Installationsloggen skrivs till:

```text
/tmp/fkextern-install.log
```

Loggen kan innehålla information om lokal miljö, paketversioner och sökvägar. Dela den inte brett om den innehåller information du inte vill sprida.

## Vad scriptet gör

Installationsscriptet gör i huvudsak detta:

1. kontrollerar att systemet är Ubuntu
2. kontrollerar att Firefox är en riktig `.deb`
3. failar om Firefox är Snap eller Flatpak
4. letar efter FK Extern-paket lokalt
5. hämtar FK Extern-paket från FK:s nedladdningsyta om det saknas lokalt
6. packar upp FK Extern-paketet
7. kontrollerar att förväntade mediafiler finns
8. rensar tidigare Citrix/Net iD-installation om reset är aktivt
9. installerar `pcscd` och kortläsarstöd
10. installerar Citrix Workspace App
11. installerar Citrix USB-stöd
12. installerar PointSharp Net iD Client
13. registrerar Net iD:s PKCS#11-modul i Firefox
14. kör grundläggande kontroll av kortläsare

## Citrix-frågor under installation

Om Citrix-installationen frågar om följande komponenter ska svaret vara `no`:

- AppProtection
- DeviceTrust
- EPAClient

## Om FK-paketet inte hittas

Om scriptet inte hittar FK-paketet på förväntad adress visas ett fel som förklarar att paketet sannolikt ersatts av en nyare version.

Åtgärden är då att uppdatera scriptet med:

- nytt paketnamn
- nytt Citrix Workspace-filnamn
- nytt Citrix USB-filnamn
- nytt Net iD-filnamn
- eventuellt justerad installationslogik

## Avgränsning och ansvar

Scriptet kör systemändringar med `sudo`, installerar paket och kan rensa tidigare Citrix/Net iD-installationer.

Läs igenom scriptet innan användning.

Jag ger ingen support på scriptet. Användaren ansvarar själv för att förstå vad scriptet gör och för att ha en fungerande arbetsmiljö.
