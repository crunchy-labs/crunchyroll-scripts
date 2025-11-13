#!/usr/bin/env bash

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <APK FILE>"
    exit 1
fi

# verify that the input file exists
echo "[·] Verifying input"
if [ ! -f "$1" ]; then
    echo "File '$1' doesn't exist"
    exit 1
fi

# verify that all necessary commands are present
echo "[·] Verifying environment"
if ! command -v jadx &> /dev/null; then
    echo "Command 'jadx' not found. Verify that it's installed and accessible by this script"
    exit 1
elif ! command -v unzip &> /dev/null; then
    echo "Command 'unzip' not found. Veritfy that it's installed and accessible by this script"
    exit 1
elif ! echo "test" | grep -P 'test' &> /dev/null; then
    echo "Command 'grep' doesn't support PCRE syntax ('-P' flag is missing). Verify that a compatible grep version is installed and accessible by this script"
    exit 1
fi

# variables
unzip_dir="$(mktemp -d)"
decompile_sources_dir="$(mktemp -d)"

echo "[·] Unzipping apk"
unzip "$1" -d "$unzip_dir"

# decompile the apk into the
echo "[·] Decompiling file (may print 'ERROR - finished with errors, count: XXX', this can safely be ignored)"
set +e
jadx \
    --output-dir-src "$decompile_sources_dir" \
    --no-res \
    "$unzip_dir/base.apk"
set -e

# extract the secrets out of the decompiled sources
if [ -f "$decompile_sources_dir/com/crunchyroll/api/util/Constants.java" ]; then
    echo "[·] Extracting secrets"
    client_id="$(cat "$decompile_sources_dir/com/crunchyroll/api/util/Constants.java" | grep -oP '(?<=\sPROD_CLIENT_ID\s=\s")\S+(?=";)')"
    client_secret="$(cat "$decompile_sources_dir/com/crunchyroll/api/util/Constants.java" | grep -oP '(?<=\sPROD_CLIENT_SECRET\s=\s")\S+(?=";)')"
else
    echo "[·] Extracting secrets, this may take a while"
    decompiled_file="$(find "$decompile_sources_dir" -type f -exec sh -c "cat '{}' | grep -q ' ConfigurationImpl.kt' && echo {}" \;)"

    constants="$(cat "$decompiled_file" | grep -n -oP '(?<==\s")\S+(?=")')"
    marker_index=$(echo "$constants" | grep -oP '\d+(?=:https://sso.crunchyroll.com)')

    client_id="$(echo $constants | grep -oP "(?<=$(($marker_index + 2)):)\S+")"
    client_secret="$(echo $constants | grep -oP "(?<=$(($marker_index + 3)):)\S+")"
fi
basic_auth_creds="$(echo -n "$client_id:$client_secret" | base64)"

# cleanup decompiled sources
echo "[·] Cleaning up"
rm -r "$unzip_dir"
rm -r "$decompile_sources_dir"

# print results
echo "[·] Finished"
echo "client id: $client_id"
echo "client secret: $client_secret"
echo "basic auth credentials: $basic_auth_creds"
