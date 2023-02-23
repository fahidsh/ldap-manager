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
function addPostfixIndexes {
    read -r -d '' postfix_indexes <<- POSTFIX_INDEXES
		dn: olcDatabase={1}mdb,cn=config
		objectclass: olcDatabaseConfig
		objectclass: olcMdbConfig
		olcdbindex: mailacceptinggeneralid eq,sub
		olcdbindex: maildrop eq    
	POSTFIX_INDEXES
    echo "$postfix_indexes" > postfix_indexes.ldif
    local LDAP_Config_Pass_Local=$(readConfigOrAsk "LDAP_Config_Pass" "Bitte geben Sie LDAP Config Passwort ein: " true)
    ldapadd -D cn=admin,cn=config -w $LDAP_Config_Pass_Local -H ldap:// -f postfix_indexes.ldif
    [ $? -eq 0 ] && rm postfix_indexes.ldif
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
        createMailUserInternal "$username" "$password"
    done < "$csvFile"
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
