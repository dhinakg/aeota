#!/usr/bin/env bash

set -e

rm -rf tmp
mkdir tmp

for i in tests/*; do
    i=$(basename "$i")
    echo "Testing $i"
    mkdir -p "tmp/$i/a" "tmp/$i/b"
    ./aastuff "tests/$i/encrypted.aea" "tmp/$i/a" "$(cat tests/"$i"/key.txt)"
    ./aastuff_standalone "tests/$i/encrypted.aea" "tmp/$i/b" "$(cat tests/"$i"/key.txt)"
    diff -r "tmp/$i/a" "tmp/$i/b" && echo "Test $i passed" || echo "Test $i failed"
done

rm -rf tmp
echo Done
