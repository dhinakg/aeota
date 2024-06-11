# aeota

AEA OTA/IPSW decryption

## `get_key.py`

Gets a key from an AEA (non OTA; for OTAs, use the key that is provided with your response).

```shell
pip3 install -r requirements.txt
python get_key.py <path to AEA>
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

## Credits

- Siguza
- Nicolas
- Snoolie
- Flagers
