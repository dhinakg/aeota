#!/usr/bin/env bash

set -e

abort() {
    echo "$1"
    exit 1
}

rm -rf tmp
mkdir tmp

for i in tests/*; do
    i=$(basename "$i")
    echo "Testing $i"
    mkdir -p "tmp/$i"
    # Ensure expected key is valid first
    aea decrypt -i "tests/$i/encrypted.aea" -o "tmp/decrypted" -key-value "base64:$(cat tests/"$i"/expected.txt)" || abort "Failed to decrypt with expected key"
    # Get the key
    python3 get_key.py "tests/$i/encrypted.aea" > "tmp/$1/actual.txt" || abort "Failed to get key"
    # Ensure the key is correct
    aea decrypt -i "tests/$i/encrypted.aea" -o "tmp/decrypted" -key-value "base64:$(cat tmp/"$i"/actual.txt)" || abort "Failed to decrypt with actual key"
    if diff -q "tmp/$i/actual.txt" "tests/$i/expected.txt"; then
        echo "Warning: key does not match expected key, but decryption was successful"
    fi
    echo "Test $i passed"
done

rm -rf tmp
echo Done
