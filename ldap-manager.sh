#!/bin/bash

<<COMMENT
*******************************************
    lesen und schreiben von config Datei
*******************************************
COMMENT

scriptPath=$(dirname "$0")
CONFIG_FILE="$scriptPath/config"

function readConfigValue() {
    if [ -f "$CONFIG_FILE" ]; then
        local key="$1"
        local value=$(grep "^$key=" "$CONFIG_FILE" | cut -d "=" -f 2)
        value=$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        echo "$value"
    else
        touch "$CONFIG_FILE"
    fi
}

function saveConfigValue() {
    [ -f "$CONFIG_FILE" ] && echo "$1=$2" >> "$CONFIG_FILE" || echo "$1=$2" > "$CONFIG_FILE"
}

function updateConfigValue() {
    local key="$1"
    local value="$2"
    if [ -f "$CONFIG_FILE" ]; then
        local val=$(readConfigValue "$key")
        [ -n "$val" ] && sed -i "s/^$key=.*/$key=$value/" "$CONFIG_FILE" || echo "$key=$value" >> "$CONFIG_FILE"
    else
        echo "$key=$value" > "$CONFIG_FILE"
    fi
}