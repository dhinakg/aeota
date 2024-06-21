# aeota

AEA OTA/IPSW decryption

## `get_key.py`

Gets a key from an AEA (non OTA; for OTAs, use the key that is provided with your response).

```shell
python3 -m venv .env
source .env/bin/activate
pip3 install -r requirements.txt
python3 get_key.py <path to AEA>
```

## Decrypting/extracting an AEA

### Non-OTAs (IPSWs)

ie. `090-34187-052.dmg.aea`

```shell
aea decrypt -i <path to AEA> -o <decrypted output file> -key-value 'base64:<key in base64>'
```

### OTAs

```shell
make
./aastuff <path to AEA> <output folder> <key in base64>
```

`aastuff` can also handle unencrypted OTAs:

```shell
aea decrypt -i <path to AEA> -o <decrypted AAR>  -key-value 'base64:<key in base64>'
./aastuff <decrypted AAR> <output folder>
```

## Notes



## Related Projects

- [aea1meta - Siguza](https://github.com/Siguza/aea1meta)

## Credits

- Siguza - auth data parsing strategy
- Nicolas - original HPKE code
- Snoolie - auth data parsing strategy
- Flagers - AppleArchive assistance
