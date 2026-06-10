#!/usr/bin/env bash

# Simple script to backup KOBO related stuff
# That includes KOReader, of course

SRC_DIR="/run/media/$USER/KOBOeReader"
BK_DIR="$HOME/Backups/kobo"

syncit() {
    # Usage: syncit src
    # Use relative link for src
    CLEAN_TARGET="$(sed 's/\./[dot]/' <<<"$1")"
    rsync -aSXHh --delete --info=NAME "$SRC_DIR/$1" "$BK_DIR/$CLEAN_TARGET"
}

if ! [ -d $SRC_DIR ]; then
    echo "Trying to mount Kobo..."
    KOBO_DEV=$(lsblk -f | awk '$0 ~ /KOBOeReader/ {print $1; exit}')

    [ -n "$KOBO_DEV" ] || {
        echo "Kobo is not plugged in."
        exit 1
    }
    udisksctl mount -b "/dev/$KOBO_DEV" || {
        echo "Failed to mount Kobo."
        exit 2
    }
fi

mkdir -p "$BK_DIR/[dot]adds/koreader"
for item in patches settings styletweaks; do
    echo "Syncing $item"
    syncit ".adds/koreader/$item/"
done

mkdir -p "$BK_DIR/[dot]adds/koreader/data"
for item in data/cr3.ini settings.reader.lua defaults.persistent.lua; do
    [ -f "$SRC_DIR/$item" ] || continue
    echo "Syncing $item"
    syncit ".adds/koreader/$item/"
done

for item in dict tessdata; do
    echo "Syncing $item"
    syncit ".adds/koreader/data/$item/"
done

mkdir -p "$BK_DIR/plugins"

declare -A official_plugins
while IFS= read -r item; do
    official_plugins["$item"]=1
done < <(curl -s 'https://api.github.com/repos/koreader/koreader/contents/plugins?ref=master' |
    jq -r '.[] | select(.type=="dir") | .name')

echo "Syncing non-official plugins..."
while IFS= read -r path; do
    name=${path##*/}
    [ -n ${official_plugins[$name]} ] && continue
    echo "  $name"
    syncit ".adds/koreader/plugins/$name.koplugin/"
done < <(find "$SRC_DIR/.adds/koreader/plugins" -mindepth 1 -maxdepth 1 -type d)

for item in nm scripts; do
    echo "Syncing $item"
    syncit ".adds/$item/"
done
echo "Syncing fonts"
syncit "fonts/"

mkdir -p "$BK_DIR/[dot]kobo"
echo "Syncing screensavers"
syncit ".kobo/screensaver/"

echo "Done!"
