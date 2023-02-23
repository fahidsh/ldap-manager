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

