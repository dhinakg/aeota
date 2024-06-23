import dataclasses
import enum
from typing import cast
import mmap
import os
import struct
import sys
import time
from pathlib import Path


class AAEntryTypes(enum.IntEnum):
    REGULAR = ord("F")
    DIRECTORY = ord("D")
    SYMBOLIC_LINK = ord("L")
    FIFO_SPECIAL = ord("P")
    CHARACTER_SPECIAL = ord("C")
    BLOCK_SPECIAL = ord("B")
    SOCKET = ord("S")
    WHITEOUT = ord("W")
    DOOR = ord("R")
    PORT = ord("T")
    METADATA = ord("M")

    def __str__(self):
        return self.name

    def __repr__(self):
        return self.name


class AAYopTypes(enum.IntEnum):
    COPY = ord("C")
    EXTRACT = ord("E")
    SRC_CHECK = ord("I")
    MANIFEST = ord("M")
    DST_FIXUP = ord("O")
    PATCH = ord("P")
    REMOVE = ord("R")

    def __str__(self):
        return self.name

    def __repr__(self):
        return self.name


class AAFieldTypes(enum.IntEnum):
    FLAG = 0
    UINT = 1
    STRING = 2
    HASH = 3
    TIMESPEC = 4
    BLOB = 5


@dataclasses.dataclass(frozen=True)
class AAFieldKey:
    name: str
    type: AAFieldTypes

    def __str__(self):
        return self.name

    def __repr__(self):
        return self.name


class AAFieldKeys(enum.Enum):
    TYPE = AAFieldKey("TYP", AAFieldTypes.UINT)
    YOP = AAFieldKey("YOP", AAFieldTypes.UINT)
    LABEL = AAFieldKey("LBL", AAFieldTypes.STRING)
    DATA = AAFieldKey("DAT", AAFieldTypes.BLOB)
    SIZE = AAFieldKey("SIZ", AAFieldTypes.UINT)
    ENTRY_OFFSET = AAFieldKey("IDX", AAFieldTypes.UINT)
    ENTRY_SIZE = AAFieldKey("IDZ", AAFieldTypes.UINT)
    PATH = AAFieldKey("PAT", AAFieldTypes.STRING)
    LINK_PATH = AAFieldKey("LNK", AAFieldTypes.STRING)
    FLAGS = AAFieldKey("FLG", AAFieldTypes.UINT)
    UID = AAFieldKey("UID", AAFieldTypes.UINT)
    GID = AAFieldKey("GID", AAFieldTypes.UINT)
    MODE = AAFieldKey("MOD", AAFieldTypes.UINT)
    MODIFICATION_TIME = AAFieldKey("MTM", AAFieldTypes.TIMESPEC)
    CREATION_TIME = AAFieldKey("CTM", AAFieldTypes.TIMESPEC)

    @classmethod
    def _missing_(cls, value):
        if isinstance(value, str):
            for member in cls:
                if member.value.name == value:
                    return member

        return super()._missing_(value)


class MemoryviewStream:
    def __init__(self, view: memoryview):
        self.view = view
        self.size = len(view)
        self.idx = 0

    def seek(self, offset: int, whence: int) -> int:
        if whence == os.SEEK_SET:
            self.idx = offset
        elif whence == os.SEEK_CUR:
            self.idx += offset
        elif whence == os.SEEK_END:
            self.idx = self.size + offset
        else:
            raise ValueError(f"Invalid whence: {whence}")

        if self.idx < 0:
            self.idx = 0

        if self.idx > self.size:
            self.idx = self.size

        return self.idx

    def read(self, n: int) -> bytes:
        if self.idx + n > self.size:
            raise ValueError(f"Attempted to read past end of stream: {self.idx + n} > {self.size}")
        with self.view[self.idx : self.idx + n] as subview:
            if len(subview) != n:
                raise ValueError(f"Expected {n} bytes, got {len(subview)}")
            result = subview.tobytes()
        self.idx += n
        return result

    def readable(self) -> bool:
        return self.idx < self.size

    def close(self) -> None:
        self.view.release()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()


# path = Path("tests/ia/decrypt_attempt.aar")
path = Path(sys.argv[1])


MAGIC_AND_HEADER = "<4sH"


def scan_range(view: memoryview, indent="", offset=0):
    with view:
        idx = 0
        while idx < len(view):
            start = idx

            magic, header_size = struct.unpack_from(MAGIC_AND_HEADER, view, idx)
            if magic != b"AA01":
                raise ValueError(f"Invalid magic at {idx}: {magic}")

            assert header_size >= 6

            header = view[start : start + header_size]
            fields = MemoryviewStream(view[idx : idx + header_size])
            idx += header_size

            blob_size = 0
            with header, fields:
                parsed_fields = {}

                fields.seek(struct.calcsize(MAGIC_AND_HEADER), os.SEEK_CUR)

                while fields.readable():
                    KEY_AND_SUBTYPE = "<3sc"
                    key, subtype = struct.unpack_from(KEY_AND_SUBTYPE, fields.read(4))
                    key = AAFieldKeys(key.decode()).value
                    subtype = cast(bytes, subtype).decode()

                    # if key in [AAFieldKeys.TYPE, AAFieldKeys.YOP]:
                    if key.type == AAFieldTypes.UINT:
                        # Int types
                        size = int(subtype)
                        assert size in [1, 2, 4, 8]
                        val = int.from_bytes(fields.read(size), "little")

                        if key == AAFieldKeys.TYPE.value:
                            val = AAEntryTypes(val)
                        elif key == AAFieldKeys.YOP.value:
                            val = AAYopTypes(val)
                    elif key.type == AAFieldTypes.STRING:
                        assert subtype == "P"
                        size = int.from_bytes(fields.read(2), "little")
                        val = fields.read(size).decode()
                    elif key.type == AAFieldTypes.BLOB:
                        value_size = {"A": 2, "B": 4, "C": 8}[subtype]
                        size = int.from_bytes(fields.read(value_size), "little")
                        val = (idx, size)

                        idx += size
                        blob_size += size
                    elif key.type == AAFieldTypes.TIMESPEC:
                        # TODO: Figure out how to represent this
                        size = {"S": 8, "T": 12}[subtype]
                        val = int.from_bytes(fields.read(size), "little")
                    else:
                        raise ValueError(f"Unknown key type: {key.type}")

                    parsed_fields[key] = val

                print(f"{indent}{start + offset:#010x}: {parsed_fields}")

                if AAFieldKeys.DATA.value in parsed_fields:
                    blob_start, blob_size = parsed_fields[AAFieldKeys.DATA.value]
                    with view[blob_start : blob_start + 4] as inner_magic:
                        # TODO: This does not handle compressed blobs
                        if inner_magic == b"AA01":
                            scan_range(view[blob_start : blob_start + blob_size], indent + "  ", offset + blob_start)

            assert start + header_size + blob_size == idx


def main():
    with path.open("rb") as f:
        with mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) as mm:
            scan_range(memoryview(mm))

            time.sleep(1)


if __name__ == "__main__":
    main()
