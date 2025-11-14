#!/usr/bin/env bash

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <APK FILE> [--info-stderr]" > /dev/stderr
    exit 1
elif [ $# -gt 1 ] && [ "$2" != "--info-stderr" ]; then
    echo "Unknown flag '$2'" > /dev/stderr
    exit 1
fi

if [ $# -eq 1 ]; then
    _OUT_INFO="/dev/stdout"
    _OUT_ERROR="/dev/stderr"
else
    _OUT_INFO="/dev/stderr"
    _OUT_ERROR="/dev/stderr"
fi

printout() {
    echo "$@" > $_OUT_INFO
}

printerr() {
    echo "$@" > $_OUT_ERROR
}

# verify that the input file exists
printout "[·] Verifying input"
if [ ! -f "$1" ]; then
    printerr "File '$1' doesn't exist"
    exit 1
fi

# verify that all necessary commands are present
printout "[·] Verifying environment"
if ! command -v jadx &> /dev/null; then
    printerr "Command 'jadx' not found. Verify that it's installed and accessible by this script"
    exit 1
elif ! command -v unzip &> /dev/null; then
    printerr "Command 'unzip' not found. Veritfy that it's installed and accessible by this script"
    exit 1
elif ! echo "test" | grep -P 'test' &> /dev/null; then
    printerr "Command 'grep' doesn't support PCRE syntax ('-P' flag is missing). Verify that a compatible grep version is installed and accessible by this script"
    exit 1
fi

# variables
scratch_dir="$(mktemp -d)"
source_file="$1"

printout "[·] Resolve file type"
source_mime_type="$(file --brief --mime-type $source_file)"
case "$source_mime_type" in
    "application/vnd.android.package-archive")
        ;;
    "application/java-archive")
        printout "[·] File is archive, unzipping it"
        mkdir "$scratch_dir/unzip"
        unzip "$source_file" -d "$scratch_dir/unzip" &> $_OUT_INFO
        source_file="$scratch_dir/unzip/base.apk"
        ;;
    *)
        printerr "Unsupported file type: $source_mime_type"
        exit 1
        ;;
esac

# decompile the apk into the
printout "[·] Decompiling file (may print 'ERROR - finished with errors, count: XXX', this can safely be ignored)"
set +e
jadx \
    --output-dir-src "$scratch_dir/decompiled" \
    --no-res \
    "$source_file" &> $_OUT_INFO
set -e

# extract the secrets out of the decompiled sources
if [ -f "$scratch_dir/decompiled/com/crunchyroll/api/util/Constants.java" ]; then
    printout "[·] Extracting secrets"
    client_id="$(cat "$scratch_dir/decompiled/com/crunchyroll/api/util/Constants.java" | grep -oP '(?<=\sPROD_CLIENT_ID\s=\s")\S+(?=";)')"
    client_secret="$(cat "$scratch_dir/decompiled/com/crunchyroll/api/util/Constants.java" | grep -oP '(?<=\sPROD_CLIENT_SECRET\s=\s")\S+(?=";)')"
else
    printout "[·] Extracting secrets, this may take a while"
    decompiled_file="$(find "$scratch_dir/decompiled" -type f -exec sh -c "cat '{}' | grep -q ' ConfigurationImpl.kt' && echo {}" \;)"

    constants="$(cat "$decompiled_file" | grep -n -oP '(?<==\s")\S+(?=")')"
    marker_index=$(echo "$constants" | grep -oP '\d+(?=:https://sso.crunchyroll.com)')

    client_id="$(echo $constants | grep -oP "(?<=$(($marker_index + 2)):)\S+")"
    client_secret="$(echo $constants | grep -oP "(?<=$(($marker_index + 3)):)\S+")"
fi
basic_auth_creds="$(echo -n "$client_id:$client_secret" | base64)"

# cleanup decompiled sources
printout "[·] Cleaning up"
rm -r "$scratch_dir"

# print results
printout "[·] Finished"
echo "client id: $client_id"
echo "client secret: $client_secret"
echo "basic auth credentials: $basic_auth_creds"
