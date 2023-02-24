#!/bin/bash

ScriptVersion="1.0.0"
ScriptAuthor="Fahid Shehzad"
ScriptAuthorURL="https://github.com/fahidsh"
ScriptDate="2020-02-23"
ScriptLastUpdate="2023-02-23"
ScriptName="ldap-manager.sh"
ScriptLicense="MIT"
ScriptInterfaceLanguage="Deutsch"

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

# zeigt die IP Adressen der Maschine (VM/Server) an
function showIpAddresses {
    echo "IP Adressen:"
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}'
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

# erstellt Postfix LDAP Schema
# https://www.postfix.org/LDAP_README.html#schema
# https://raw.githubusercontent.com/68b32/postfix-ldap-schema/master/postfix.ldif
function addPostfixSchema {
    read -r -d '' postfix_ldif <<- POSTFIX_LDIF
		dn: cn=postfix,cn=schema,cn=config
		cn: postfix
		objectclass: olcSchemaConfig
		olcattributetypes: {0}(1.3.6.1.4.1.4203.666.1.200 NAME 'mailacceptinggeneral
		 id' DESC 'Postfix mail local address alias attribute' EQUALITY caseIgnoreMa
		 tch SUBSTR caseIgnoreSubstringsMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{1
		 024})
		olcattributetypes: {1}(1.3.6.1.4.1.4203.666.1.201 NAME 'maildrop' DESC 'Post
		 fix mail final destination attribute' EQUALITY caseIgnoreMatch SUBSTR caseI
		 gnoreSubstringsMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{1024})
		olcobjectclasses: {0}(1.3.6.1.4.1.4203.666.1.100 NAME 'postfixUser' DESC 'Po
		 stfix mail user class' SUP top AUXILIARY MAY(mailacceptinggeneralid $ maild
		 rop))
	POSTFIX_LDIF
    echo "$postfix_ldif" > postfix.ldif
    local LDAP_Config_Pass_Local=$(readConfigOrAsk "LDAP_Config_Pass" "Bitte geben Sie LDAP Config Passwort ein: " true)
    ldapadd -D cn=admin,cn=config -w $LDAP_Config_Pass_Local -H ldap:// -f "postfix.ldif"
    [ $? -eq 0 ] && rm postfix.ldif
}

# erstellt Postfix LDAP Indexe
# Depriziert, produzierte Fehler
function addPostfixIndexesDeprecated {
    read -r -d '' postfix_indexes <<- POSTFIX_INDEXES
		dn: olcDatabase={1}mdb,cn=config
		objectClass: olcDatabaseConfig
		objectClass: olcMdbConfig
		olcDatabase: {1}mdb
		olcDbDirectory: /var/lib/ldap
		olcDbIndex: mailacceptinggeneralid eq,sub
		olcDbIndex: maildrop eq    
	POSTFIX_INDEXES
    echo "$postfix_indexes" > postfix_indexes.ldif
    local LDAP_Config_Pass_Local=$(readConfigOrAsk "LDAP_Config_Pass" "Bitte geben Sie LDAP Config Passwort ein: " true)
    ldapadd -D cn=admin,cn=config -w $LDAP_Config_Pass_Local -H ldap:// -f postfix_indexes.ldif
    [ $? -eq 0 ] && rm postfix_indexes.ldif
}

# erstellt Postfix LDAP Indexe
function addPostfixIndexes {
    # aktuelle Zeit ermitteln
    timestamp=$(date +%Y%m%d%H%M%S)
    # backup ordner festlegen und erstellen
    backupDir="/var/backup/ldap_backup_idx_$timestamp"
    sudo mkdir -p "$backupDir"
    # LDAP Konfiguration in einer Datei sichern
    sudo slapcat -n 0 -l "$backupDir/config.ldif"
    sudo slapcat -n 1 -l "$backupDir/data.ldif"
    newIndexes="olcDbIndex: mailacceptinggeneralid eq,sub\nolcDbIndex: maildrop eq"
    # neue Indexe in Konfiguration einfügen
    sudo sed "/olcDbIndex: member,memberUid eq/a $newIndexes" "$backupDir/config.ldif" > "$backupDir/new-config.ldif"
    # LDAP Dienst stoppen
    sudo pkill slapd
    sudo mkdir -p "$backupDir/slapd.d"
    sudo cp -r /etc/ldap/slapd.d "$backupDir/slapd.d"
    sudo rm -rf /etc/ldap/slapd.d/*
    sudo mkdir -p "$backupDir/slapd"
    sudo cp -r /var/lib/ldap "$backupDir/slapd"
    sudo rm -rf /var/lib/ldap/*
    sudo slapadd -n 0 -F /etc/ldap/slapd.d -l "$backupDir/new-config.ldif"
    sudo slapadd -n 1 -F /etc/ldap/slapd.d -l "$backupDir/data.ldif"
    sudo chown -R openldap:openldap /etc/ldap/slapd.d
    sudo chown -R openldap:openldap /var/lib/ldap
    sudo systemctl start slapd
}

# erstellt einen neuen Benutzer in LDAP Datenbank mit dem Namen "mailAccountReader"
# diser Benutzer kann alle LDAP Objekte (ohne Passwört) unter ou=Mail,dc=example,dc=com lesen
# es wird für LDAP Bind in Postfix (und weiteren) benötigt
function addMailAccountReader {
    checkLdapDomain
    local passwordHash=$(slappasswd -s "mar")
    read -r -d '' mailAccountReader <<- MAILACCOUNTREADER
		dn: cn=mailAccountReader,ou=Manager,$LDAP_Prefix
		objectClass: organizationalRole
		objectClass: simpleSecurityObject
		objectClass: top
		cn: mailAccountReader
		userPassword: $passwordHash
	MAILACCOUNTREADER
    echo "$mailAccountReader" > mailAccountReader.ldif
    local LDAP_Admin_Pass_Local=$(readConfigOrAsk "LDAP_Admin_Pass" "Bitte geben Sie LDAP Admin Passwort ein: " true)
    ldapadd -D "cn=admin,$LDAP_Prefix" -w $LDAP_Admin_Pass_Local -H ldap:// -f "mailAccountReader.ldif"
    [ $? -eq 0 ] && rm mailAccountReader.ldif
}

# erstellt ACL für mailAccountReader
# erlaubt dem Benutzer "mailAccountReader" alle LDAP Objekte (ohne Passwört) unter ou=Mail,dc=example,dc=com lesen
function addMailAccountReaderACL {
    checkLdapDomain
    read -r -d '' mailAccountReaderACL <<- MAILACCOUNTREADER_ACL
		dn: olcDatabase={1}mdb,cn=config
		changetype: modify
		add: olcAccess
		olcAccess: {0}to attrs=userPassword
		  by self =xw
		  by anonymous auth
		  by * none
		olcAccess: {1}to dn.subtree="ou=Mail,$LDAP_Prefix"
		  by dn.base="cn=mailAccountReader,ou=Manager,$LDAP_Prefix" read
		  by * none
	MAILACCOUNTREADER_ACL
    echo "$mailAccountReaderACL" > mailAccountReaderACL.ldif
    local LDAP_Config_Pass_Local=$(readConfigOrAsk "LDAP_Config_Pass" "Bitte geben Sie LDAP Config Passwort ein: " true)
    ldapadd -D cn=admin,cn=config -w $LDAP_Config_Pass_Local -H ldap:// -f mailAccountReaderACL.ldif
    [ $? -eq 0 ] && rm mailAccountReaderACL.ldif
}

# erstellt einen neuen Benutzer in LDAP Datenbank unter ou=Mail,dc=example,dc=com
# Benutzername und Passwort werden als Parameter übergeben
# Parameter: $1 = Benutzername
# Parameter: $2 = Passwort
function createMailUser {
    if [ -z "$1" ] || [ -z "$2" ]; then
        return 1
    else
        local username="$1"
        local password="$2"
    fi

    checkLdapDomain
    local passwordHash=$(slappasswd -s "$password")
    local cuid=$(getNextUid)
    local emailAddress="$username@$LDAP_Domain"
    local mailDropAddress="$username@$Hostname"

    read -r -d '' mail_user <<- MAIL_USER
		dn: uid=$username,ou=Mail,$LDAP_Prefix
		cn: $username
		gidnumber: $cuid
		homedirectory: /home/mail/$username
		mailacceptinggeneralid: $emailAddress
		maildrop: $mailDropAddress
		objectclass: account
		objectclass: posixAccount
		objectclass: postfixUser
		objectclass: top
		uid: $username
		uidnumber: $cuid
		userpassword: $passwordHash
	MAIL_USER
    echo "$mail_user" > mail_user.ldif
    local LDAP_Admin_Pass_Local=$(readConfigOrAsk "LDAP_Admin_Pass" "Bitte geben Sie LDAP Admin Passwort ein: " true)
    ldapadd -D "cn=admin,$LDAP_Prefix" -w $LDAP_Admin_Pass_Local -H ldap:// -f "mail_user.ldif"
    [ $? -eq 0 ] && rm mail_user.ldif
}

# erstellt einen neuen Benutzer in LDAP Datenbank unter ou=Mail,dc=example,dc=com
# Benutzername und Passwort werden über die Konsole eingegeben
function createMailUserInteractive {
    echo "Neuen Mail Benutzer erstellen..."
    read -p "Benutzername: " mailUsername
    read -s -p "Passwort: " mailPassword
    createMailUser "$mailUsername" "$mailPassword"
}

# erstellt Benutzer in LDAP Datenbank unter ou=Mail,dc=example,dc=com
# Benutzerdaten werden aus CSV Datei eingelesen
function importMailUsersFromCsv {
    echo "Importiere Mail Benutzer aus CSV..."
    echo "CSV-Format: [username,password]"
    echo "----------------------------------"
    echo "Bitte geben Sie den Pfad zur CSV Datei ein."
    read -p "CSV Datei: " csvFile

    if [ ! -f "$csvFile" ]; then
        echo "Datei '$csvFile' existiert nicht, bitte gibb Komplett-Pfad."
        return
    fi

    while IFS=, read -r username password; do
        if [[ "$username" == \#* ]]; then
            continue
        fi
        # leerzeichen entfernen (trim)
        username=$(echo "$username" | xargs)
        password=$(echo "$password" | xargs)
        createMailUserInternal "$username" "$password"
        #echo -e "User: $username\nPasswort: $password\n"
    done < "$csvFile"
}

function createSampleMailUserImportCsv {
    echo "Erstelle Beispiel CSV Datei für Benutzer Import..."
    read -r -d '' sample_mail_users_import_csv <<- SAMPLE_MAIL_USERS_IMPORT_CSV
		# Sample CSV
		# Format: username,password
		# Lines starting with # will be ignored, treated as comments
		# username,password
		max,0000
		erika.mustermann,1111
		john_doe,mypass
		jane,doe
	SAMPLE_MAIL_USERS_IMPORT_CSV
    echo "$sample_mail_users_import_csv" > sample_mail_users_import.csv
    echo "Sample CSV Datei erstellt: $scriptPath/sample_mail_users_import.csv"
    
}

# erstellt eine neue Gruppe in LDAP Datenbank unter ou=Mail,dc=example,dc=com
function createMailGroup {
    if [ -z "$1" ]; then
        return
    else
        local groupName="$1"
    fi
    checkLdapDomain

    read -r -d '' mail_group <<- MAIL_GROUP
		dn: cn=$groupName,ou=Mail,$LDAP_Prefix
		objectClass: groupOfUniqueNames
		objectClass: top
		cn: $groupName
		uniqueMember: uid=test,ou=Mail,$LDAP_Prefix
	MAIL_GROUP
    echo "$mail_group" > mail_group.ldif
    local LDAP_Admin_Pass_Local=$(readConfigOrAsk "LDAP_Admin_Pass" "Bitte geben Sie LDAP Admin Passwort ein: " true)
    ldapadd -D "cn=admin,$LDAP_Prefix" -w $LDAP_Admin_Pass_Local -H ldap:// -f "mail_group.ldif"
    [ $? -eq 0 ] && rm mail_group.ldif
}

# erstellt eine neue Gruppe in LDAP Datenbank unter ou=Mail,dc=example,dc=com
# Gruppenname wird über die Konsole eingegeben
function createMailGroupInteractive {
    echo "Neue Mail Gruppe erstellen..."
    read -p "Gruppenname: " mailGroupName
    createMailGroup "$mailGroupName"
}

# installiert Postfix Mailserver
function installPostfix {
    echo "Installiere Postfix..."
    checkUpdates
    sudo apt-get install postfix postfix-ldap -y
}

# stellt die allgemeine LDAP Konfig-Parameters für Postfix LDAP-Tabellen zur Verfügung
function getpostfixCommons {
    checkLdapDomain
    read -r -d '' postfix_common <<- POSTFIX_COMMON
		server_host = ldap://$Hostname
		start_tls = no
		version = 3
		bind = yes
		bind_dn = cn=mailAccountReader,ou=Manager,$LDAP_Prefix
		bind_pw = mar
		search_base = ou=Mail,$LDAP_Prefix
		scope = sub
	POSTFIX_COMMON
    echo "$postfix_common"
}

# erstellt die LDAP Konfigurationstabellen für Postfix
function generatePostfixLdapMaps {
    local postfix_common=$(getpostfixCommons)
    local basePath="/etc/postfix/ldap"
    mkdir -p "$basePath"

    read -r -d '' virtual_alias_domains <<- POSTFIX_VIRTUAL_ALIAS_DOMAINS
		query_filter = mailacceptinggeneralid=*@%s
		result_attribute = mailacceptinggeneralid
		result_format = %d
	POSTFIX_VIRTUAL_ALIAS_DOMAINS
    echo "$postfix_common" > "$basePath/virtual_alias_domains"
    echo "$virtual_alias_domains" >> "$basePath/virtual_alias_domains"

    read -r -d '' virtual_alias_maps <<- POSTFIX_VIRTUAL_ALIAS_MAPS
		query_filter = mailacceptinggeneralid=%s
		result_attribute = maildrop
	POSTFIX_VIRTUAL_ALIAS_MAPS
    echo "$postfix_common" > "$basePath/virtual_alias_maps"
    echo "$virtual_alias_maps" >> "$basePath/virtual_alias_maps"

    read -r -d '' virtual_mailbox_maps <<- POSTFIX_VIRTUAL_MAILBOX_MAPS
		query_filter = maildrop=%s
		result_attribute = homeDirectory
		result_format = %s/mailbox/
	POSTFIX_VIRTUAL_MAILBOX_MAPS
    echo "$postfix_common" > "$basePath/virtual_mailbox_maps"
    echo "$virtual_mailbox_maps" >> "$basePath/virtual_mailbox_maps"

    read -r -d '' virtual_uid_maps <<- POSTFIX_VIRTUAL_UID_MAPS
		query_filter = maildrop=%s
		result_attribute = uidNumber
	POSTFIX_VIRTUAL_UID_MAPS
    echo "$postfix_common" > "$basePath/virtual_uid_maps"
    echo "$virtual_uid_maps" >> "$basePath/virtual_uid_maps"

    read -r -d '' smtpd_sender_login_maps <<- POSTFIX_SMTPD_SENDER_LOGIN_MAPS
		query_filter = (|(mailacceptinggeneralid=%s)(maildrop=%s))
		result_attribute = uid
	POSTFIX_SMTPD_SENDER_LOGIN_MAPS
    echo "$postfix_common" > "$basePath/smtpd_sender_login_maps"
    echo "$smtpd_sender_login_maps" >> "$basePath/smtpd_sender_login_maps"

    sudo chown postfix:postfix /etc/postfix/ldap/*
    sudo chmod 400 /etc/postfix/ldap/*

    sudo systemctl restart postfix
}

# testet die LDAP Konfigurationstabellen für Postfix
function testPostfixLdapTables {
    checkLdapDomain
    echo "Teste Postfix LDAP Tabellen..."
    sudo postmap -q $LDAP_Domain ldap:/etc/postfix/ldap/virtual_alias_domains
    sudo postmap -q test@$Hostname ldap:/etc/postfix/ldap/virtual_mailbox_maps
    sudo postmap -q test@$Hostname ldap:/etc/postfix/ldap/virtual_uid_maps
    sudo postmap -q test@$LDAP_Domain ldap:/etc/postfix/ldap/smtpd_sender_login_maps
    sudo postmap -q test@$LDAP_Domain ldap:/etc/postfix/ldap/virtual_alias_maps
}

# erstellt die allgemein Konfiguration für Postfix, main.cf
function configurePostfixMainCf {
    read -r -d '' postfix_main <<- POSTFIX_MAIN
		myhostname = $Hostname
		smtpd_banner = $Hostname ESMTP (Ubuntu)
		biff = no
		append_dot_mydomain = no
		mydestination = localhost.fahid.de, localhost
		relayhost =
		mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128 10.0.0.0/8 192.168.0.0/16
		mailbox_size_limit = 0
		recipient_delimiter = +
		inet_interfaces = all
		smtpd_relay_restrictions = permit_mynetworks reject_unauth_destination
		smtpd_recipient_restrictions = reject_sender_login_mismatch
		virtual_alias_domains = ldap:/etc/postfix/ldap/virtual_alias_domains
		virtual_mailbox_domains = $Hostname

		virtual_alias_maps = ldap:/etc/postfix/ldap/virtual_alias_maps
		virtual_mailbox_base = /
		virtual_mailbox_maps = ldap:/etc/postfix/ldap/virtual_mailbox_maps
		virtual_uid_maps = ldap:/etc/postfix/ldap/virtual_uid_maps
		virtual_gid_maps = ldap:/etc/postfix/ldap/virtual_uid_maps

		smtpd_sender_login_maps = ldap:/etc/postfix/ldap/smtpd_sender_login_maps
	POSTFIX_MAIN

    sudo mv /etc/postfix/main.cf /etc/postfix/main.cf.bak
    sudo echo "$postfix_main" > /etc/postfix/main.cf
    sudo mkdir -p /home/mail
    sudo chmod o+w /home/mail
}

function sendTestMail {
    read -p "Sender: " sender
    read -p "Recipient: " recipient
    # read -p "Subject: " subject
    subject="Testmail"

    /usr/sbin/sendmail -v -i -t <<- MESSAGE_END
		From: $sender
		To: $recipient
		Subject: $subject

		Hola amigo, que pasa contigo? 
		kommt die Mail an? Lasst uns testen!
	MESSAGE_END
}

# installiert Dovecot
function installDovecot {
    checkUpdates
    sudo apt install dovecot-core dovecot-imapd dovecot-ldap -y
}

# konfiguriert Dovecot
function configureDovecot {
    checkLdapDomain
    read -r -d '' mail_conf <<- MAIL_CONF
		#protocols = imap
		mail_location = maildir:~/mailbox
		namespace inbox {
		    inbox = yes
		}
		mail_privileged_group = mail

		protocol !indexer-worker {
		}    
	MAIL_CONF
    sudo mv /etc/dovecot/conf.d/10-mail.conf /etc/dovecot/conf.d/10-mail.conf.bak
    sudo echo "$mail_conf" > /etc/dovecot/conf.d/10-mail.conf

    read -r -d '' master_conf <<- MASTER_CONF
		service imap-login {
		  inet_listener imap {
		    port = 143
		  }
		  inet_listener imaps {
		    #port = 993
		    #ssl = yes
		  }
		  service_count = 1
		  process_min_avail = 1
		}

		service pop3-login {
		  inet_listener pop3 {
		    port = 110
		  }
		  inet_listener pop3s {
		    #port = 995
		    #ssl = yes
		  }
		}
	MASTER_CONF
    sudo mv /etc/dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-master.conf.bak
    sudo echo "$master_conf" > /etc/dovecot/conf.d/10-master.conf

    read -r -d '' auth_conf <<- AUTH_CONF
		auth_mechanisms = plain login
		disable_plaintext_auth = no
		!include auth-system.conf.ext
		!include auth-ldap.conf.ext
	AUTH_CONF
    sudo mv /etc/dovecot/conf.d/10-auth.conf /etc/dovecot/conf.d/10-auth.conf.bak
    sudo echo "$auth_conf" > /etc/dovecot/conf.d/10-auth.conf

    read -r -d '' auth_ldap_conf <<- AUTH_LDAP_CONF
		passdb {
		  driver = ldap
		  args = /etc/dovecot/dovecot-ldap.conf.ext
		}
		userdb {
		  driver = ldap
		  args = /etc/dovecot/dovecot-ldap.conf.ext
		}
	AUTH_LDAP_CONF
    sudo mv /etc/dovecot/conf.d/auth-ldap.conf.ext /etc/dovecot/conf.d/auth-ldap.conf.ext.bak
    sudo echo "$auth_ldap_conf" > /etc/dovecot/conf.d/auth-ldap.conf.ext

    read -r -d '' dovecot_ldap_conf <<- DOVECOT_LDAP_CONF
		uris = ldap://$Hostname
		dn = cn=mailAccountReader,ou=Manager,$LDAP_Prefix
		dnpass = mar
		#tls = yes
		#tls_ca_cert_file = /etc/ldap/tls/CA.pem
		#tls_require_cert = hard
		debug_level = 0
		auth_bind = yes
		auth_bind_userdn = uid=%u,ou=Mail,$LDAP_Prefix
		ldap_version = 3
		base = ou=Mail,$LDAP_Prefix
		scope = subtree
		user_attrs = homeDirectory=home,uidNumber=uid,gidNumber=gid
		user_filter = (&(objectClass=posixAccount)(uid=%u))
	DOVECOT_LDAP_CONF
    sudo mv /etc/dovecot/dovecot-ldap.conf.ext /etc/dovecot/dovecot-ldap.conf.ext.bak
    sudo echo "$dovecot_ldap_conf" > /etc/dovecot/dovecot-ldap.conf.ext

    systemctl restart dovecot
}

# installiert Apache2, PHP und MySQL
function installLampStack {
    checkUpdates
    sudo apt install apache2 mariadb-server mariadb-client zip unzip php libmagickcore-6.q16-6-extra -y

    sudo apt install php-{apcu,bcmath,cli,common,curl,ldap,gd,gmp,imagick,net-smtp,json,intl,mbstring,mysql,zip,xml,net-smtp,pear,bz2,imap,auth-sasl,mail-mime,net-ldap3,net-sieve,curl} -y

    sudo phpenmod bcmath gmp imagick intl mbstring zip xml
    sudo chown -R www-data:www-data /var/www/html
    sudo systemctl enable mariadb
    sudo mysql_secure_installation    

    read -r -d '' php_ini <<- PHP_INI
		max_execution_time = 360
		memory_limit = 512M
		post_max_size = 200M
		upload_max_filesize = 200M
		date.timezone = Europe/Berlin
		opcache.enable=1
		opcache.memory_consumption=128
		opcache.interned_strings_buffer=8
		opcache.max_accelerated_files=10000
		opcache.revalidate_freq=1
		opcache.save_comments=1
	PHP_INI
    phpVersion=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "." -f 1-2)
    sudo mv "/etc/php/$phpVersion/apache2/php.ini" "/etc/php/$phpVersion/apache2/php.ini.bak"
    sudo echo "$php_ini" > "/etc/php/$phpVersion/apache2/php.ini"    
    sudo systemctl restart apache2
}

# installiert Nextcloud
function installNextcloud {
    wget -4 https://download.nextcloud.com/server/installer/setup-nextcloud.php
    sudo mv setup-nextcloud.php /var/www/html/
    sudo chown -R www-data:www-data /var/www/html/setup-nextcloud.php

    # nextcloud data ordner nicht im webroot
    sudo mkdir /home/nextcloud
    sudo chown -R www-data:www-data /home/nextcloud
    # erstelle Datenbank und Benutzer für Nextcloud
    local MYSQL_Root_Pass_Local=$(readConfigOrAsk "MYSQL_Root_Pass" "Bitte geben Sie MYSQL_Root_Pass Passwort ein: " true)
    local dbObjektName="nextcloud"
    sudo mysql -uroot -p$MYSQL_Root_Pass_Local -e "CREATE DATABASE $dbObjektName /*\!40100 DEFAULT CHARACTER SET utf8 */;"
    sudo mysql -uroot -p$MYSQL_Root_Pass_Local -e "CREATE USER $dbObjektName@localhost IDENTIFIED BY '$dbObjektName';"
    sudo mysql -uroot -p$MYSQL_Root_Pass_Local -e "GRANT ALL PRIVILEGES ON $dbObjektName.* TO '$dbObjektName'@'localhost';"
    sudo mysql -uroot -p$MYSQL_Root_Pass_Local -e "FLUSH PRIVILEGES;"
    sudo systemctl restart apache2

    read -r -d '' notice_text <<- NOTICE_TEXT
		************************************************************************************************
		bitte besuchen Sie ein den folgenden Link um Nextcloud zu installieren:
		$(showWithAllIpAddresses "http://IP_ADDRESS/setup-nextcloud.php")
		************************************************************************************************
		Benutzen Sie die folgenden MySQL Datenbank Daten:
		Datenbank:                  $dbObjektName
		Datenbank Benutzer:         $dbObjektName
		Datenbank Passwort:         $dbObjektName
		--------- Weitere Konfig Parameter ---------
		Nextcloud Datenordner:      /home/nextcloud
	NOTICE_TEXT
    echo "$notice_text"
}

# installiert Roundcube
function installRoundcube {
    VER=1.5.2
    sudo wget -4 https://github.com/roundcube/roundcubemail/releases/download/$VER/roundcubemail-$VER-complete.tar.gz
    sudo mkdir /var/www/html/roundcube
    sudo tar xzf roundcubemail-$VER-complete.tar.gz -C /var/www/html/roundcube --strip-components 1
    sudo chown -R www-data:www-data /var/www/html/roundcube
    sudo chmod -R 755 /var/www/html/roundcube

    # erstelle Datenbank und Benutzer für Nextcloud
    local MYSQL_Root_Pass_Local=$(readConfigOrAsk "MYSQL_Root_Pass" "Bitte geben Sie MYSQL_Root_Pass Passwort ein: " true)
    local dbObjektName="roundcube"
    sudo mysql -uroot -p$MYSQL_Root_Pass_Local -e "CREATE DATABASE $dbObjektName /*\!40100 DEFAULT CHARACTER SET utf8 */;"
    sudo mysql -uroot -p$MYSQL_Root_Pass_Local -e "CREATE USER $dbObjektName@localhost IDENTIFIED BY '$dbObjektName';"
    sudo mysql -uroot -p$MYSQL_Root_Pass_Local -e "GRANT ALL PRIVILEGES ON $dbObjektName.* TO '$dbObjektName'@'localhost';"
    sudo mysql -uroot -p$MYSQL_Root_Pass_Local -e "FLUSH PRIVILEGES;"
    sudo mysql -u$dbObjektName -p$dbObjektName $dbObjektName < /var/www/html/roundcube/SQL/mysql.initial.sql
    sudo systemctl restart apache2

    read -r -d '' notice_text <<- NOTICE_TEXT
		************************************************************************************************
		bitte besuchen Sie ein den folgenden Link um Roundcube zu installieren:
        $(showWithAllIpAddresses "http://IP_ADDRESS/roundcube/installer")
		************************************************************************************************
		Benutzen Sie die folgenden MySQL Datenbank Daten:
		Datenbank:                  $dbObjektName
		Datenbank Benutzer:         $dbObjektName
		Datenbank Passwort:         $dbObjektName
        --------- Weitere Konfig Parameter ---------

	NOTICE_TEXT
    echo "$notice_text"
}

# LDAP Authentifizierung für Apache aktivieren
function setApacheLdapAuth {
    checkLdapDomain
    auth_dir="authenticated"
    auth_dir_full="/var/www/html/$auth_dir"
    sudo mkdir $auth_dir_full
    sudo chown -R www-data:www-data $auth_dir_full
    sudo chmod -R 755 $auth_dir_full
    #sudo a2enmod authnz_ldap proxy_http
    sudo a2enmod authnz_ldap

    read -r -d '' index_php_authenticate <<- INDEX_PHP_AUTHENTICATE
		<h1>Authenticated</h1>
		<?php
		if (isset(\$_SERVER['PHP_AUTH_USER'])) {
            \$user = \$_SERVER['PHP_AUTH_USER'];
		    echo "<h2>Welcome Mr. \$user, you are authenticated.</h2>";
		}
		?>
	INDEX_PHP_AUTHENTICATE
    sudo echo "$index_php_authenticate" > "$auth_dir_full/index.php"

    read -r -d '' apache_ldap_auth_conf <<- APACHE_LDAP_AUTH_CONF
		<VirtualHost *:80>
		    #ServerName $Hostname
		    ServerAdmin webmaster@localhost
		    DocumentRoot /var/www/html/
		    ErrorLog \${APACHE_LOG_DIR}/error.log
		    CustomLog \${APACHE_LOG_DIR}/access.log combined
		    <Directory /$auth_dir_full>
		        Options Indexes FollowSymLinks MultiViews
		        AllowOverride None
		        Order deny,allow
		        Deny from All

		        AuthType Basic
		        AuthName "LDAP Authentication"
		        AuthBasicProvider ldap
		        AuthBasicAuthoritative Off
		        AuthLDAPURL "ldap://127.0.0.1:389/ou=Mail,$LDAP_Prefix?uid?sub?(objectClass=*)"
		        AuthLDAPBindDN "cn=mailAccountReader,ou=Manager,$LDAP_Prefix"
		        AuthLDAPBindPassword "mar"
		        Require valid-user
		        Satisfy any
		    </Directory>
		</VirtualHost>
	APACHE_LDAP_AUTH_CONF
    sudo echo "$apache_ldap_auth_conf" > /etc/apache2/sites-available/ldap-auth.conf
    sudo a2ensite ldap-auth.conf
    sudo a2dissite 000-default.conf
    sudo systemctl restart apache2
}

# LDAP Authentifizierung für Apache deaktivieren
function deactivateApacheLdapAuth {
    sudo a2dissite ldap-auth.conf
    sudo a2ensite 000-default.conf
    sudo a2dismod authnz_ldap
    sudo systemctl restart apache2
}

# Liest alle IP Adressen aus und ersetzt IP_ADDRESS mit der IP Adresse in der übergebenen Zeichenkette
# Parameter: $1 = Zeichenkette in der IP_ADDRESS ersetzt werden soll
function showWithAllIpAddresses {
    [ -z "$1" ] && return
    local text="$1"
    local preText="        ->"
    #allIpAddresses=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo "$preText ${text//IP_ADDRESS/$Hostname}"
    while IFS= read -r line; do
        echo "$preText ${text//IP_ADDRESS/$line}"
    done <<< "$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
}

function showAbout {
    read -r -d '' about_text <<- ABOUT_TEXT
		*******************************************
		************    About    ******************
		*******************************************
		Skript Name:            $0
		Skript Version:         $ScriptVersion
		Skript Author:          $ScriptAuthor ( $ScriptAuthorURL )
		Skript Lizenz:          $ScriptLicense
		Oberfläche Sprache:     $ScriptLanguage
		Skript Datum:           $ScriptDate
		Skript Letzte Änderung: $ScriptLastChange
		*******************************************
		Referenzen:
		  - https://www.vennedey.net/resources/2-LDAP-managed-mail-server-with-Postfix-and-Dovecot-for-multiple-domains
		  - https://medium.com/@uri.tau/apache-and-ldap-cc7bff1f629d
		  - https://stackoverflow.com/

	ABOUT_TEXT
    echo "$about_text"
}

<<COMMENT
*******************************************
    Menü
*******************************************
COMMENT
function displayMenu {
    read -r -d '' menu_text <<- MENU_TEXT
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
	MENU_TEXT
    echo "$menu_text"
    read -p "Bitte wählen Sie einen Option: " option
    echo
}

EnterPromptMessage="Drücke die Eingabe Taste um fortzufahren..."
if [ "$EUID" -eq 0 ]; then
    # menu anzeigen bis X gewählt wird
    while [ "$option" != "X" ]; do
        displayMenu
        case $option in
            1)
                echo "Auf dieser Server wird LDAP, Postfix, Dovecot und Web Server installiert/konfiguriert."
                echo "Bitte geben Sie die benötigten Daten ein."
                echo "Falls Sie abbrechen wollen drücken Sie STRG+C"
                read -p "$EnterPromptMessage"
                setHostname
                installLDAP
                configureLDAP
                resetConfigPassword
                addPostfixSchema
                # erstelle OU für Mail
                createOU "Mail"
                # erstelle OU für Manager
                createOU "Manager"
                createMailUser "test" "test"
                createMailGroup "Test Group"
                addMailAccountReader
                addMailAccountReaderACL
                addPostfixIndexes
                installPostfix
                generatePostfixLdapMaps
                configurePostfixMainCf
                testPostfixLdapTables
                installDovecot
                configureDovecot
                installLampStack
                installNextcloud
                read -p "$EnterPromptMessage"
                installRoundcube
                read -p "$EnterPromptMessage"
                ;;
            10)
                echo "Setze Hostname..."
                setHostname
                read -p "$EnterPromptMessage"
                ;;
            11)
                echo -n "Aktuelle Hostname: "
                echo $Hostname
                read -p "$EnterPromptMessage"
                ;;
            12)
                showIpAddresses
                read -p "$EnterPromptMessage"
                ;;
            20)
                installLDAP
                configureLDAP
                resetConfigPassword
                read -p "$EnterPromptMessage"
                ;;
            21)
                installLDAP
                read -p "$EnterPromptMessage"
                ;;
            22)
                configureLDAP
                read -p "$EnterPromptMessage"
                ;;
            23)
                resetConfigPassword
                read -p "$EnterPromptMessage"
                ;;
            24)
                createOuInteractive
                read -p "$EnterPromptMessage"
                ;;
            25)
                createMailUserInteractive
                read -p "$EnterPromptMessage"
                ;;
            26)
                importMailUsersFromCsv
                read -p "$EnterPromptMessage"
                ;;
            27)
                createSampleMailUserImportCsv
                read -p "$EnterPromptMessage"
                ;;
            30)
                addPostfixSchema
                # erstelle OU für Mail
                createOU "Mail"
                # erstelle OU für Manager
                createOU "Manager"
                createMailUser "test" "test"
                createMailGroup "Test Group"
                addMailAccountReader
                addMailAccountReaderACL
                addPostfixIndexes
                read -p "$EnterPromptMessage"
                ;;
            40)
                installPostfix
                generatePostfixLdapMaps
                configurePostfixMainCf
                testPostfixLdapTables
                read -p "$EnterPromptMessage"
                ;;
            41)
                installPostfix
                read -p "$EnterPromptMessage"
                ;;
            42)
                generatePostfixLdapMaps
                configurePostfixMainCf
                read -p "$EnterPromptMessage"
                ;;
            43)
                testPostfixLdapTables
                read -p "$EnterPromptMessage"
                ;;
            50)
                installDovecot
                configureDovecot
                read -p "$EnterPromptMessage"
                ;;
            51)
                installDovecot
                read -p "$EnterPromptMessage"
                ;;
            52)
                configureDovecot
                read -p "$EnterPromptMessage"
                ;;
            60)
                installLampStack
                installNextcloud
                installRoundcube
                read -p "$EnterPromptMessage"
                ;;
            61)
                installLampStack
                read -p "$EnterPromptMessage"
                ;;
            62)
                installNextcloud
                read -p "$EnterPromptMessage"
                ;;
            63)
                installRoundcube
                read -p "$EnterPromptMessage"
                ;;
            68)
                echo "Apache LDAP Auth Aktiviert"
                echo "http://$Hostname/authenticated"
                setApacheLdapAuth
                read -p "$EnterPromptMessage"
                ;;
            69)
                echo "Apache LDAP Auth Deaktiviert"
                deactivateApacheLdapAuth
                read -p "$EnterPromptMessage"
                ;;
            90)
                echo "Development..."
                echo "nothing to do..."
                read -p "$EnterPromptMessage"
                ;;
            99)
                showAbout
                read -p "$EnterPromptMessage"
                ;;

            X | x)
                echo "Beende..."
                echo "--------------------"
                echo "Bitte schauen Sie die Datei: $CONFIG_FILE"
                echo "es können wichtige Passwörter gespeichert sein."
                echo "löschen Sie die Zeilen mit Passwörtern wenn Sie diese nicht mehr benötigen."
                echo "--------------------"
                option="X"
                ;;
            *)
                echo "Ungültige Eingabe!: $option"
                read -p "$EnterPromptMessage"
                ;;
        esac
    done
else
    echo "Bitte führen Sie das Script als root aus."
fi
