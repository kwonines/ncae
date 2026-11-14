#!/bin/bash
set -Eeuo pipefail

if [[ $# -ne 1 || ! -f $1 || ! -r $1 ]]; then
    printf 'Usage: %s readable-key-file\n' "$0" >&2
    exit 2
fi

if [[ $EUID -ne 0 ]]; then
    printf 'Run this script as root.\n' >&2
    exit 1
fi

key_file=$1

find /home -mindepth 1 -maxdepth 1 -type d -print0 |
while IFS= read -r -d '' home; do
    ssh_dir="$home/.ssh"
    auth_file="$ssh_dir/authorized_keys"

    read -r uid gid < <(stat -c '%u %g' -- "$home")

    if [[ -L $ssh_dir || ( -e $ssh_dir && ! -d $ssh_dir ) ]]; then
        printf 'Skipping %s: .ssh is not a real directory.\n' "$home" >&2
        exit 1
    fi

    mkdir -p -- "$ssh_dir"
    chown "$uid:$gid" -- "$ssh_dir"
    chmod 700 -- "$ssh_dir"

    if [[ -L $auth_file || ( -e $auth_file && ! -f $auth_file ) ]]; then
        printf 'Skipping %s: authorized_keys is not a regular file.\n' "$home" >&2
        exit 1
    fi

    if [[ -e $auth_file && $key_file -ef $auth_file ]]; then
        printf 'Skipping %s: key file is the authorized_keys file.\n' "$home" >&2
        exit 1
    fi

    tmp_file=$(mktemp -- "$ssh_dir/.authorized_keys.XXXXXX")

    if [[ -f $auth_file ]]; then
        cp -- "$auth_file" "$tmp_file"
    fi

    while IFS= read -r key_line || [[ -n $key_line ]]; do
        [[ -z $key_line ]] && continue

        if ! grep -Fqx -- "$key_line" "$tmp_file"; then
            if [[ -s $tmp_file ]] && [[ $(tail -c 1 -- "$tmp_file" | wc -l) -eq 0 ]]; then
                printf '\n' >> "$tmp_file"
            fi
            printf '%s\n' "$key_line" >> "$tmp_file"
        fi
    done < "$key_file"

    chown "$uid:$gid" -- "$tmp_file"
    chmod 600 -- "$tmp_file"
    mv -fT -- "$tmp_file" "$auth_file"

    printf 'Updated %s\n' "$auth_file"
done
