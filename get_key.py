#!/usr/bin/env python3

# Modified from Nicolas's initial script
# Thx to Siguza and Snoolie for AEA auth block parsing information

# Requirements: pip3 install requests pyhpke

import argparse
import base64
import json
import sys
from pathlib import Path
from pprint import pprint

import requests
from pyhpke import AEADId, CipherSuite, KDFId, KEMId, KEMKey

AEA_PROFILE__HKDF_SHA256_AESCTR_HMAC__SYMMETRIC__NONE = 1

suite = CipherSuite.new(KEMId.DHKEM_P256_HKDF_SHA256, KDFId.HKDF_SHA256, AEADId.AES256_GCM)


def error(msg):
    print(msg, file=sys.stderr)
    exit(1)


def main(aea_path: Path, verbose: bool = False):
    fields = {}
    with aea_path.open("rb") as f:
        header = f.read(12)
        if len(header) != 12:
            error(f"Expected 12 bytes, got {len(header)}")

        magic = header[:4]
        if magic != b"AEA1":
            error(f"Invalid magic: {magic.hex()}")

        profile = int.from_bytes(header[4:7], "little")
        if profile != AEA_PROFILE__HKDF_SHA256_AESCTR_HMAC__SYMMETRIC__NONE:
            error(f"Invalid AEA profile: {profile}")

        auth_data_blob_size = int.from_bytes(header[8:12], "little")

        if auth_data_blob_size == 0:
            error("No auth data blob")

        auth_data_blob = f.read(auth_data_blob_size)
        if len(auth_data_blob) != auth_data_blob_size:
            error(f"Expected {auth_data_blob_size} bytes, got {len(auth_data_blob)}")

        assert auth_data_blob[:4]

        while len(auth_data_blob) > 0:
            field_size = int.from_bytes(auth_data_blob[:4], "little")
            field_blob = auth_data_blob[:field_size]

            key, value = field_blob[4:].split(b"\x00", 1)

            fields[key.decode()] = value.decode()

            auth_data_blob = auth_data_blob[field_size:]

    if verbose:
        pprint(fields, stream=sys.stderr)

    if "com.apple.wkms.fcs-response" not in fields:
        error("No fcs-response field found!")

    if "com.apple.wkms.fcs-key-url" not in fields:
        error("No fcs-key-url field found!")

    fcs_response = json.loads(fields["com.apple.wkms.fcs-response"])
    enc_request = base64.b64decode(fcs_response["enc-request"])
    wrapped_key = base64.b64decode(fcs_response["wrapped-key"])
    url = fields["com.apple.wkms.fcs-key-url"]

    r = requests.get(url, timeout=10)
    r.raise_for_status()

    privkey = KEMKey.from_pem(r.text)

    recipient = suite.create_recipient_context(enc_request, privkey)
    pt = recipient.open(wrapped_key)

    if verbose:
        print(f"Key: {base64.b64encode(pt).decode()}")
    else:
        print(base64.b64encode(pt).decode())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Get the key for an AEA file")
    parser.add_argument("path", help="Path to the AEA file")
    parser.add_argument("-v", "--verbose", action="store_true", help="Show verbose output")
    args = parser.parse_args()

    main(Path(args.path), args.verbose)
