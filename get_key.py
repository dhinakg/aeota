#!/usr/bin/env python3

# Modified from Nicolas's initial script
# Thx to Siguza and Snoolie for AEA auth block parsing information

# Requirements: pip3 install requests pyhpke

import base64
import json
from pathlib import Path
from sys import argv

import requests
from pyhpke import AEADId, CipherSuite, KDFId, KEMId, KEMKey

AEA_PROFILE__HKDF_SHA256_AESCTR_HMAC__SYMMETRIC__NONE = 1

suite = CipherSuite.new(KEMId.DHKEM_P256_HKDF_SHA256, KDFId.HKDF_SHA256, AEADId.AES256_GCM)

if len(argv) < 2:
    print("Usage: get_key.py <aea>")
    exit(1)


aea_path = Path(argv[1])
fields = {}
with aea_path.open("rb") as f:
    header = f.read(12)
    if len(header) != 12:
        print(f"Expected 12 bytes, got {len(header)}")
        exit(1)

    magic = header[:4]
    if magic != b"AEA1":
        print(f"Invalid magic: {magic.hex()}")
        exit(1)

    profile = int.from_bytes(header[4:7], "little")
    if profile != AEA_PROFILE__HKDF_SHA256_AESCTR_HMAC__SYMMETRIC__NONE:
        print(f"Invalid AEA profile: {profile}")
        exit(1)

    auth_data_blob_size = int.from_bytes(header[8:12], "little")

    auth_data_blob = f.read(auth_data_blob_size)
    if len(auth_data_blob) != auth_data_blob_size:
        print(f"Expected {auth_data_blob_size} bytes, got {len(auth_data_blob)}")
        exit(1)

    assert auth_data_blob[:4]

    while len(auth_data_blob) > 0:
        field_size = int.from_bytes(auth_data_blob[:4], "little")
        field_blob = auth_data_blob[:field_size]

        key_end = field_blob.index(b"\x00", 4)
        key = field_blob[4:key_end].decode()
        value = field_blob[key_end + 1 :].decode()
        fields[key] = value

        auth_data_blob = auth_data_blob[field_size:]


print(fields, "\n")

if "com.apple.wkms.fcs-response" not in fields:
    print("No fcs-response field found, is this from an OTA?")
    exit(1)

fcs_response = json.loads(fields["com.apple.wkms.fcs-response"])
enc_request = base64.b64decode(fcs_response["enc-request"])
wrapped_key = base64.b64decode(fcs_response["wrapped-key"])
url = fields["com.apple.wkms.fcs-key-url"]

r = requests.get(url, timeout=10)
r.raise_for_status()


privkey = KEMKey.from_pem(r.text)

recipient = suite.create_recipient_context(enc_request, privkey)
pt = recipient.open(wrapped_key)

print(f"Key: {base64.b64encode(pt).decode()}")
