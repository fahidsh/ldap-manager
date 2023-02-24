# LDAP-Manager
LDAP-Manager ist ein bash-Skript, welches es ermöglicht, LDAP-Server zu installieren, konfigurieren und es als Authentifizierungbackend für Postfix und Dovecot zu verwenden.

Es sind einige zusätzliche Funktionen implementiert, wie z.B. 
 - das Erstellen von Benutzern, Gruppen, Organisational Units.
 - das Installieren von Apache2, PHP und MySQL.
 - Installation von Nextcloud und Roundcube.
 - Konfigurieren von Apache URL mit LDAP-Authentifizierung.

## Installation
Der Skript braucht an sich keine Installation, aber es installiert einige Pakete, die benötigt werden. Dazu muss das Skript als **root** ausgeführt werden.

## Vorraussetzungen
 - Root-Rechte
 - Ubuntu 20.04, 22.04
 - Internetverbindung

> **Hinweis:** <br> LDAP-Manager wurde nur auf Ubuntu 20.04 und 22.04 getestet, es könnte aber auch auf anderen Debian-basierten Distributionen funktionieren, ist aber nicht getestet.

## Konfiguration
Der Skript braucht kein Konfiguration, es speichert aber die Konfiguration in der Datei **config**. Diese Datei wird beim ersten Start des Skripts, in der aktuellen Arbeitsverzeichnis, erstellt. Die Konfiguration kann jederzeit bearbeitet werden. Die konfig Datei ist als **root** erstellt, deswegen muss sie auch als root bearbeitet werden. In die konfig Datei werden sämtliche Parameter gespeichert, die für die Installation und Funktion des Skripts benötigt werden. Darunter werden auch Passwörter in Klar Text gespeichert, deswegen sollte die konfig Datei nur von root gelesen werden können. Die konfig Datei vereinfacht die Verwendung von dieser Skript, kann aber nach jedem Skript-Session (von Benutzer) gelöscht werden.

## Benutzung
Der Skript kann mit folgenden Befehlen gestartet werden:
``` bash
sudo ./ldap-manager.sh

# oder

sudo bash ldap-manager.sh
```
nach der Skript-Start wird ein Text-Menü angezeigt, wo verschiedene Optionen zur Verfügung stehen. Die Optionen sind meisten selbsterklärend und werden im Menü erklärt, oder so ist es gewünscht. Benutzer kann das **Nummer** von gewünschte Option eingeben und mit **Enter** bestätigen. Wenn die Option **Nummer** nicht existiert, wird eine Fehlermeldung angezeigt und das Menü wird wieder angezeigt. Der Skript kann mit **x** oder **X** beendet werden.

### Beispiel Menü
``` bash
-----------------------------------------------------
1)  Installiere LDAP, Postfix, Dovecot und Web Server
-----------------------------------------------------
10) Hostname setzen
11) Aktuelle Hostname auslesen
12) IP Adresseen auslesen
-----------------------------------------------------
20) LDAP installieren und konfigurieren
21) LDAP installieren
22) LDAP konfigurieren
23) LDAP Config Passwort [cn=admin,cn=config] zurücksetzen
24) Erstelle OU
25) Erstelle E-Mail Benutzer
26) E-Mail Benutzer von CSV Datei importieren
27) Erstelle Beispiel Benutzer Import CSV Datei
-----------------------------------------------------
41) Postfix installieren und konfigurieren
41) Postfix installieren
42) Postfix konfigurieren
43) Postfix LDAP-Tabellen testen
-----------------------------------------------------
50) Dovecot installieren und konfigurieren
51) Dovecot installieren
52) Dovecot konfigurieren
-----------------------------------------------------
60) LAMP-Stack mit Nextcloud und Roundcube installieren
61) LAMP-Stack installieren
62) Nextcloud installieren
63) Roundcube installieren
68) Apache LDAP Authentifizierung aktivieren
69) Apache LDAP Authentifizierung deaktivieren
-----------------------------------------------------
99) Über
-----------------------------------------------------
X)  Exit
-----------------------------------------------------
Bitte wählen Sie einen Option:
```
hier z.B. mit eingabe von **20** wird die Option **LDAP installieren und konfigurieren** gestartet.

Nach dem der ausgewählte Option beendet ist, wird das Menü wieder angezeigt, bis man es mit **x** oder **X** beendet.

## Importieren von Benutzern aus CSV Datei
Der Skript kann Benutzer aus einer CSV Datei importieren. Die CSV Datei ist genz einfach und besteht aus zwei Spalten, **Benutzername** und **Passwort**. z.B.:

``` csv
fahid,0000
john,123456
# diese Zeile ist ein Kommentar, wird ignoriert
max,myPa55W0rd
```
Zeilen, die mit ein **#** beginnen, werden wie Kommentar behandelt und ignoriert.

---

## Lizenz
Dieses Skript ist unter der **MIT License** lizensiert. Siehe Siehe [MIT License](https://opensource.org/licenses/MIT) für mehr Informationen.

## Haftungsausschluss
Dieses Skript ist für den persönlichen Gebrauch bestimmt. Es wird nicht für kommerzielle Zwecke verwendet. Ich übernehme keine Haftung für Schäden, die durch die Verwendung dieses Skripts entstehen. Sie verwenden dieses Skript auf eigene Gefahr.

## Autor
Dieses Skript wurde von [Fahid Shehzad](https://github.com/fahidsh) geschrieben.