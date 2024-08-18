# aeota

AEA OTA/IPSW decryption

## Prerequisites

- `get_key.py`
  - Python 3.10+ (might work with older, but not tested)
  - `requests`
  - `pyhpke`
- `aastuff`
  - macOS 13+
  - macOS 14+ for HPKE support
- `aastuff_standalone`
  - macOS 12+
  - macOS 14+ for HPKE support

## Building and Installing

### `get_key.py`

```shell
pip3 install -r requirements.txt
```

> [!NOTE]
> It is highly recommended to use a virtual environment:
>
> ```shell
> python3 -m venv .env  # only needed once
> source .env/bin/activate
> pip3 install -r requirements.txt  # only needed once
> ```
>
> On future runs, you only need to activate the virtual environment:
>
> ```shell
> source .env/bin/activate
> ```

### `aastuff`/`aastuff_standalone`

You can pass two options to the makefile:

- `DEBUG=1`: build debug (debug prints, no optimizations, debug information)
- `HPKE=1`: build with HPKE support (needs macOS 14.0+)

```shell
make [DEBUG=1] [HPKE=1]
```

## Grabbing keys with `get_key.py`

Unwrap the decryption key using the data embedded in an AEA's auth data blob.

> [!NOTE]
> OTAs before iOS 18.0 beta 3 did not have embedded auth data; for these OTAs, you must use the decryption key provided with your response. macOS is the exception and has always had embedded auth data.

```shell
source .env/bin/activate  # if you used a virtual environment
python3 get_key.py <path to AEA>
```

## Decrypting an AEA

```shell
aea decrypt -i <path to AEA> -o <decrypted output file> -key-value 'base64:<key in base64>'
# or
./aastuff -i <path to AEA> -o <decrypted output folder> -d -k <key in base64>
# or, to use the network to grab the private key
./aastuff -i <path to AEA> -o <decrypted output folder> -d -n
```

For IPSWs, you will get the unwrapped file (ie. `090-34187-052.dmg.aea` will decrypt to `090-34187-052.dmg`).

For assets, you will get specially crafted Apple Archives (see next section).

## Extracting assets

Assets (including OTA updates) are constructed specially and cannot be extracted with standard (`aa`) tooling. They can be decrypted normally, which will result in an Apple Archive that is not extractable with `aa` (we will call these "asset archives"). `aastuff` must be used to extract them.

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

> [!NOTE]
> `aastuff_standalone` has more features, including file listings and selective extraction. Run `./aastuff_standalone -h` for full usage information.

## Notes

`aastuff` uses `AAAssetExtractor`, functions from `libAppleArchive` in order to extract asset archives. However, it is a pretty barren API and does not offer things like selective extraction.

`aastuff_standalone` uses (mostly) standard `libAppleArchive` functions to extract asset archives. It offers things such as file listings and selective extraction, but is not fully validated against all possible asset archives.

For now, both are built and used in the same way. Once `aastuff_standalone` is fully functional and validated, `aastuff` will be deprecated.

## Related Projects

- [aea1 - Siguza](https://github.com/Siguza/aea1)

## Credits

- Siguza - auth data parsing strategy, Apple Archive extraction sample code
- Nicolas - original HPKE code
- Snoolie - auth data parsing strategy
- Flagers - Apple Archive assistance
