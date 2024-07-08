# aeota

AEA OTA/IPSW decryption

## Grabbing keys with `get_key.py`

Gets a key from an AEA (non OTA; for OTAs, use the key that is provided with your response, as they generally do not have embedded key acquisition metadata).

```shell
pip3 install -r requirements.txt
python3 get_key.py <path to AEA>
```

Note: it is highly recommended to use a virtual environment:

```shell
python3 -m venv .env  # only needed once
source .env/bin/activate
pip3 install -r requirements.txt  # only needed once
python3 get_key.py <path to AEA>
```

## Decrypting an AEA

```shell
aea decrypt -i <path to AEA> -o <decrypted output file> -key-value 'base64:<key in base64>'
```

For IPSWs, you will get the unwrapped file (ie. `090-34187-052.dmg.aea` will decrypt to `090-34187-052.dmg`).

For assets, you will get specially crafted AppleArchives (see next section).

## Extracting assets

Assets (including OTA updates) are constructed specially and cannot be extracted with standard (`aa`) tooling. They can be decrypted normally, which will result in an AppleArchive that is not extractable with `aa` (we will call these "asset archives"). `aastuff` must be used to extract them.

```shell
# Decrypt if necessary
aea decrypt -i <path to AEA> -o <decrypted asset archive> -key-value 'base64:<key in base64>'
./aastuff -i <decrypted asset archive> -o <output folder>
```

`aastuff` can also handle asset archives that are not already decrypted:

```shell
./aastuff -i <path to AEA> -o <output folder> -k <key in base64>
```

Run `./aastuff -h` for full usage information.

## Notes

`aastuff` uses `AAAssetExtractor`, functions from `libAppleArchive` in order to extract asset archives. However, it is a pretty barren API and does not offer things like selective extraction.

`aastuff_standalone` uses (mostly) standard `libAppleArchive` functions to extract asset archives. In the future (but not currently), it will be able to offer things such as file listings and selective extraction.

For now, both are built and used in the same way. Once `aastuff_standalone` is fully functional and validated, `aastuff` will be deprecated.

## Related Projects

- [aea1 - Siguza](https://github.com/Siguza/aea1)

## Credits

- Siguza - auth data parsing strategy, AppleArchive extraction sample code
- Nicolas - original HPKE code
- Snoolie - auth data parsing strategy
- Flagers - AppleArchive assistance
