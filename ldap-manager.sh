#!/bin/bash

<<COMMENT
*******************************************
    lesen und schreiben von config Datei
*******************************************
COMMENT
# Pfad des Skripts
scriptPath=$(dirname "$0")
# Pfad der config Datei
CONFIG_FILE="$scriptPath/config"

# Lese den Wert einer Konfigurationsvariable aus der config Datei
# Parameter: $1 = Name der Konfigurationsvariable
function readConfigValue() {
    [ -z "$1" ] && echo "" && return    
    if [ -f "$CONFIG_FILE" ]; then
        local key="$1"
        local value=$(grep "^$key=" "$CONFIG_FILE" | cut -d "=" -f 2)
        value=$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        echo "$value"
    else
        touch "$CONFIG_FILE"
    fi
}

# Lese den Wert einer Konfigurationsvariable aus der config Datei
# wenn der Wert leer ist, dann den Benutzer nach dem Wert fragen
# Parameter: $1 = Name der Konfigurationsvariable
# optional   $2 = Text der angezeigt wird, wenn der Benutzer nach dem Wert gefragt wird
# optional   $3 = true/false, wenn true, dann wird der Wert nicht angezeigt
function readConfigOrAsk() {
    local key="$1"
    local value=$(readConfigValue "$key")
    if [ -z "$value" ]; then
        local prmpt="Bitte geben Sie einen Wert für $key ein:"
        [ -n "$2" ] && prmpt="$2"
        if [ -n "$3" ] && [ "$3" = true ]; then
            read -sp "$prmpt" value
        else
            read -p "$prmpt" value
        fi
        saveConfigValue "$key" "$value"
    fi
    echo "$value"
}

# Speichert einen Wert in der config Datei
# if der Wert schon existiert, dann wird er überschrieben
# Parameter: $1 = Name der Konfigurationsvariable
#            $2 = Wert der Konfigurationsvariable
function saveConfigValue() {
    [ -z "$1" ] && return
    [ -z "$2" ] && return
    local val=$(readConfigValue "$1")
    [ -n "$val" ] && updateConfigValue "$1" "$2"
    [ -f "$CONFIG_FILE" ] && echo "$1=$2" >> "$CONFIG_FILE" || echo "$1=$2" > "$CONFIG_FILE"
}

# Aktualisiert der Wert einer Konfigurationsvariable in der config Datei
# Parameter: $1 = Name der Konfigurationsvariable
#            $2 = Wert der Konfigurationsvariable
function updateConfigValue() {
    [ -z "$1" ] && return
    [ -z "$2" ] && return
    local key="$1"
    local value="$2"
    if [ -f "$CONFIG_FILE" ]; then
        local val=$(readConfigValue "$key")
        [ -n "$val" ] && sed -i "s/^$key=.*/$key=$value/" "$CONFIG_FILE" || echo "$key=$value" >> "$CONFIG_FILE"
    else
        echo "$key=$value" > "$CONFIG_FILE"
    fi
}


<<COMMENT
*******************************************
    Variablen die am Anfang gesetzt werden
*******************************************
COMMENT
# LDAP Domain aus der config Datei lesen
LDAP_Domain=$(readConfigValue "LDAP_Domain")
# wenn LDAP Domain nicht leer ist, dann LDAP Prefix setzen
[ -n "$LDAP_Domain" ] && LDAP_Prefix=$(echo $LDAP_Domain | sed 's/\./,dc=/g' | sed 's/^/dc=/')
# variable um die nächste UID/GUID zu ermitteln
# zu letzt verwendete UID/GUID aus der config Datei lesen
LDAP_uid=$(readConfigValue "LDAP_uid")
# LDAP admin passwort aus der config Datei lesen
# es ist der dc=admin,dc=example,dc=com passwort
LDAP_Admin_Pass=$(readConfigValue "LDAP_Admin_Pass")
# LDAP config passwort aus der config Datei lesen
# es ist der cn=admin,cn=config passwort
LDAP_Config_Pass=$(readConfigValue "LDAP_Config_Pass")
# MYSQL Root Passwort aus der config Datei lesen
MYSQL_Root_Pass=$(readConfigValue "MYSQL_Root_Pass")
# variable um den status der apt update zu speichern
# bei jede start der script (Skript-Session) wird es auf false gesetzt
# nach ausführen von apt update wird es auf true gesetzt
isAptUpdate=false
# Hostname der Maschine (VM/Server)
Hostname=$(hostname -f)


<<COMMENT
*******************************************
    Funktionen um bestimmte werte aus der config Datei zu lesen
*******************************************
COMMENT
# liest die zu letzt verwendete UID/GUID aus der config Datei
# erhöht die UID/GUID um 1 und speichert die neue UID/GUID in der config Datei
function getNextUid {
    LDAP_uid=$(readConfigValue "LDAP_uid")
    # prüfe ob LDAP_uid leer ist
    # wenn ja, dann setze LDAP_uid auf 20000
    [ -z "$LDAP_uid" ] && LDAP_uid=20000
    # erhöhe LDAP_uid um 1
    local LDAP_uid_local=$(($LDAP_uid + 1))
    # speichere LDAP_uid in config Datei
    updateConfigValue "LDAP_uid" $LDAP_uid_local
    # gebe LDAP_uid zurück
    echo "$LDAP_uid_local"
}

# prüft ob apt update schon in der aktuellen Skript-Session ausgeführt worden ist
# wenn nicht, dann führt es aus
function checkUpdates {
    if [ "$isAptUpdate" = false ]; then
        sudo apt update
        #sudo apt upgrade -y
        isAptUpdate=true
    fi
}

# prüft ob die LDAP Domain oder LDAP Prefix leer ist
# wenn ja, dann fragt es den Benutzer nach der LDAP Domain
function checkLdapDomain {
    while [ -z "$LDAP_Domain" ] || [ -z "$LDAP_Prefix" ]; do
        read -p "Bitte geben Sie ihre LDAP-Domäne ein: " LDAP_Domain
        if [ -z "$LDAP_Domain" ]; then
            echo "LDAP Domäne darf nicht leer sein"
        else
            LDAP_Prefix=$(echo $LDAP_Domain | sed 's/\./,dc=/g' | sed 's/^/dc=/')
            updateConfigValue "LDAP_Domain" $LDAP_Domain
            updateConfigValue "LDAP_Prefix" $LDAP_Prefix
        fi
    done    
}


<<COMMENT
*******************************************
    Weitere Funktionen 
*******************************************
COMMENT
# setzt den Hostname der Maschine (VM/Server)
# Benutzer wird nach dem Hostname gefragt
# wenn der Hostname leer ist, dann wird der aktuelle Hostname verwendet
function setHostname {
    echo "Aktueller Hostname ist: $Hostname"
    echo "Es ist empfohlen den Hostname als FQDN anzugeben. kann aber nur der Hostname sein."
    read -p "Hostname z.B.[ldap.itschule.de oder ldapserver]: " hostname
    # prüfe ob Hostname leer ist, wenn nicht setze Hostname
    [ -z "$hostname" ] || (sudo hostnamectl set-hostname $hostname && echo "127.0.0.1 $hostname" >> /etc/hosts)
    Hostname=$(hostname -f)
    echo "Hostname ist: $Hostname"
}

# installiert die LDAP Server
function installLDAP {
    checkUpdates
    sudo apt install slapd ldap-utils -y
    echo
}

# starte den LDAP konfigurationswizard
function configureLDAP {
    sudo dpkg-reconfigure slapd
}

# fragt den Benutzer nach ein neuen Passwort mit Bestätigung
# es muss zwei mal das gleiche Passwort eingegeben werden
function getMatchingPassword {
    passwordPrompt="Bitte geben Sie Passwort ein"
    [ -n "$1" ] && passwordPrompt="$1"
    while true; do
        read -s -p "$passwordPrompt: " password
        echo
        read -s -p "Bitte Bestätigen Sie das Passwort: " password2
        [ "$password" = "$password2" ] && break
        echo
        echo "Passwörter stimmen nicht überein, versuchen Sie noch einmal."
    done
    echo
    #echo "$password"
}

# setzt das Passwort für den LDAP Config cn=admin,cn=config
# Benutzer wird nach dem neuen Passwort gefragt
# Es wird ein Backup der LDAP Konfiguration und Daten erstellt
# das neue Passwort wird in die LDAP Konfiguration Backup Datei hinzugefügt
# die LDAP Konfiguration und Daten werden mit dem neuen Passwort wiederhergestellt
function resetConfigPassword {
    # Benuzer nach dem neuen Passwort fragen
    getMatchingPassword "Bitte geben Sie neue Passwort für cn=admin,cn=config ein"
    # neues Passwort in die config Datei schreiben
    updateConfigValue "LDAP_Config_Pass" "$password"
    # passwort hash erzeugen
    passwordHash=$(slappasswd -s $password)
    # aktuelle Zeit ermitteln
    timestamp=$(date +%Y%m%d%H%M%S)
    # backup ordner festlegen und erstellen
    backupDir="/var/backup/ldap_backup_$timestamp"
    sudo mkdir -p "$backupDir"
    # LDAP Konfiguration in einer Datei sichern
    sudo slapcat -n 0 -l "$backupDir/config.ldif"
    # LDAP Daten sichern
    sudo slapcat -n 1 -l "$backupDir/data.ldif"
    # Neue Passwort in die LDAP Konfiguration Sicherung hinzufügen und in eine neue Datei schreiben
    if grep -q "olcRootDN: cn=admin,cn=config" "$backupDir/config.ldif"; then
        sudo sed "/olcRootDN: cn=admin,cn=config/a olcRootPW: $passwordHash" "$backupDir/config.ldif" > "$backupDir/new-config.ldif"
    else
        sudo sed "/olcDatabase: {0}config/a olcRootDN: cn=admin,cn=config\nolcRootPW: $passwordHash" "$backupDir/config.ldif" > "$backupDir/new-config.ldif"
    fi
    # LDAP Dienst stoppen
    sudo pkill slapd
    # sicher die aktuelle LDAP Konfiguration in der Backup Ordner
    sudo mkdir -p "$backupDir/slapd.d"
    sudo cp -r /etc/ldap/slapd.d "$backupDir/slapd.d"
    # aktuelle LDAP konfiguration löschen
    sudo rm -rf /etc/ldap/slapd.d/*
    # sicher die aktuelle LDAP Datenbank in der Backup Ordner
    sudo mkdir -p "$backupDir/slapd"
    sudo cp -r /var/lib/ldap "$backupDir/slapd"
    # aktuelle LDAP Datenbank löschen
    sudo rm -rf /var/lib/ldap/*
    # die Sicherung von LDAP Konfiguration mit dem neuen Passwort importieren
    sudo slapadd -n 0 -F /etc/ldap/slapd.d -l "$backupDir/new-config.ldif"
    # die Sicherung von LDAP Daten importieren
    sudo slapadd -n 1 -F /etc/ldap/slapd.d -l "$backupDir/data.ldif"
    # Inhaber der LDAP Konfiguration und Datenbank auf openldap ändern
    sudo chown -R openldap:openldap /etc/ldap/slapd.d
    sudo chown -R openldap:openldap /var/lib/ldap
    # LDAP Dienst starten
    sudo systemctl start slapd
    # prüfe ob LDAP Dienst läuft
    #sudo systemctl status slapd
}

# erstellt neue Top-Level Organisational Unit (OU) in LDAP Datenbank
# Parameter $1: Name der OU
# Optional  $2: Beschreibung der OU
function createOU {
    [ -z "$1" ] && return
    checkLdapDomain
    echo "dn: ou=$1,$LDAP_Prefix" > ou.ldif
    echo "objectClass: organizationalUnit" >> ou.ldif
    echo "objectClass: top" >> ou.ldif
    echo "ou: $1" >> ou.ldif
    [ -z "$2" ] || echo "description: $2" >> ou.ldif
    local LDAP_Admin_Pass_Local=$(readConfigOrAsk "LDAP_Admin_Pass" "Bitte geben Sie LDAP Admin Passwort ein: " true)
    ldapadd -D "cn=admin,$LDAP_Prefix" -w $LDAP_Admin_Pass_Local -H ldap:// -f "ou.ldif"
    [ $? -eq 0 ] && rm ou.ldif
}

# erstellt neue Organisational Unit (OU) in LDAP Datenbank
# Benutzer wird nach dem Namen und Beschreibung der OU gefragt
function createOuInteractive {
    read -p "Name der OU: " ouName
    read -p "Beschreibung der OU: " ouDescription
    createOU "$ouName" "$ouDescription"
}
