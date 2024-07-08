#!/usr/bin/env bash

set -e
set -o pipefail

# Use aa list instead of full decryption
FAST=1
FAILED=0

fail() {
    echo "$1"
    echo ""
    if [ "$CI" = "true" ]; then
        FAILED=1
    else
        exit 1
    fi
}

rm -rf tmp
mkdir tmp

for i in tests/*; do
    i=$(basename "$i")
    echo "Testing $i"
    if [ -e "tests/$i/skip_get_key" ]; then
        echo "Skipping $i"
        echo ""
        continue
    fi

    if [ -e "test/$i/fast_unsupported" ]; then
        FAST=0
    fi

    TEST_DIR="tests/$i"
    TMP_DIR="tmp/$i"

    mkdir -p "$TMP_DIR"

    ret=0

    # Ensure expected key is valid first
    if [ "$FAST" -eq 1 ]; then
        aa list -i "$TEST_DIR/encrypted.aea" -key-value "base64:$(cat tests/"$i"/expected.txt)" || ret=$?
    else
        aea decrypt -i "$TEST_DIR/encrypted.aea" -o "/dev/null" -key-value "base64:$(cat tests/"$i"/expected.txt)" || ret=$?
    fi

    if [ $ret -ne 0 ]; then
        fail "Failed to decrypt with expected key"
        continue
    fi

    # Get the key
    python3 get_key.py "$TEST_DIR/encrypted.aea" | tr -d '\n' >"$TMP_DIR/actual.txt" || ret=$?
    if [ $ret -ne 0 ]; then
        fail "Failed to get key"
        continue
    fi

    # Ensure the key is correct
    if [ "$FAST" -eq 1 ]; then
        aa list -i "$TEST_DIR/encrypted.aea" -key-value "base64:$(cat tmp/"$i"/actual.txt)" || ret=$?
    else
        aea decrypt -i "$TEST_DIR/encrypted.aea" -o "/dev/null" -key-value "base64:$(cat tmp/"$i"/actual.txt)" || ret=$?
    fi

    if [ $ret -ne 0 ]; then
        fail "Failed to decrypt with actual key"
        continue
    fi

    diff "$TMP_DIR/actual.txt" "$TEST_DIR/expected.txt" || ret=$?
    if [ $ret -ne 0 ]; then
        echo "Warning: key does not match expected key, but decryption was successful"
    fi

    echo "Test $i passed"
    echo ""
done

rm -rf tmp
echo Done

if [ $FAILED -ne 0 ]; then
    echo "Some tests failed"
    exit 1
fi
