#!/usr/bin/env bash

set -e
set -o pipefail

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
mkdir -p tmp

for i in tests/*; do
    i=$(basename "$i")
    TEST_DIR="tests/$i"
    TMP_DIR="tmp/$i"

    echo "Testing $i"

    if [ -f "$TEST_DIR/skip_extract" ]; then
        echo "Skipping $i"
        echo ""
        continue
    fi

    mkdir -p "$TMP_DIR/a" "$TMP_DIR/b"

    ret=0

    if [[ ! -f "$TEST_DIR/expected.txt" ]]; then
        fail "Missing expected.txt"
        continue
    fi

    if [[ ! -f "$TEST_DIR/flags.txt" ]]; then
        fail "Missing flags.txt"
        continue
    fi

    ./aastuff -i "tests/$i/encrypted.aea" -o "tmp/$i/a" --key "$(cat "$TEST_DIR"/expected.txt)" || ret=$?
    if [ $ret -ne 0 ]; then
        fail "aastuff failed with $ret"
        continue
    fi

    ./aastuff_standalone -i "tests/$i/encrypted.aea" -o "tmp/$i/b" --key "$(cat "$TEST_DIR"/expected.txt)" || ret=$?
    if [ $ret -ne 0 ]; then
        fail "aastuff_standalone failed with $ret"
        continue
    fi

    diff -r "$TMP_DIR/a" "$TMP_DIR/b" || ret=$?
    if [ $ret -eq 0 ]; then
        echo "Diff passed"
    else
        fail "Diff failed"
        continue
    fi

    aa archive -d "tmp/$i/a" -o "tmp/$i/a.aar" -exclude-field all -include-field "$(cat tests/"$i"/flags.txt)" || ret=$?
    if [ $ret -ne 0 ]; then
        fail "Archive creation failed with $ret"
        continue
    fi

    aa verify -i "tmp/$i/a.aar" -d "tmp/$i/b" || ret=$?
    if [ $ret -eq 0 ]; then
        echo "Verify passed"
    else
        fail "Verify failed"
        continue
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
