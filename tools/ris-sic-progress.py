"""Read completion masks from MATLAB v7 checkpoints using the standard library."""
import argparse
import json
import math
from pathlib import Path
import struct
import zlib


def elements(data, endian):
    pos = 0
    while pos + 8 <= len(data):
        tag, size = struct.unpack_from(endian + "II", data, pos)
        small_size = tag >> 16
        if small_size:
            yield tag & 0xFFFF, data[pos + 4:pos + 4 + small_size]
            pos += 8
        else:
            payload = data[pos + 8:pos + 8 + size]
            if len(payload) != size:
                raise ValueError("Truncated MAT element")
            if tag == 15:  # Compressed top-level elements have no padding.
                yield from elements(zlib.decompress(payload), endian)
                pos += 8 + size
            else:
                yield tag, payload
                pos += 8 + ((size + 7) // 8) * 8


def completion(path):
    raw = path.read_bytes()
    if len(raw) < 128 or raw[126:128] not in (b"IM", b"MI"):
        raise ValueError(f"Not a MATLAB v5/v7 file: {path}")
    endian = "<" if raw[126:128] == b"IM" else ">"
    for kind, payload in elements(raw[128:], endian):
        if kind != 14:  # miMATRIX
            continue
        fields = list(elements(payload, endian))
        if len(fields) < 4 or fields[2][1] != b"completed":
            continue
        dims = struct.unpack(endian + "i" * (len(fields[1][1]) // 4), fields[1][1])
        mask = fields[3][1]
        if fields[3][0] != 2 or len(mask) != math.prod(dims):
            raise ValueError(f"Unexpected completion-mask layout: {path}")
        if any(value not in (0, 1) for value in mask):
            raise ValueError(f"Nonlogical completion mask: {path}")
        return sum(mask), len(mask)
    raise ValueError(f"Missing completion mask: {path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sample_dir", type=Path)
    parser.add_argument("--mc-total", type=int, default=60)
    parser.add_argument("--snr-count", type=int, default=7)
    parser.add_argument("--summary", action="store_true")
    args = parser.parse_args()
    rows = []
    for path in sorted(args.sample_dir.glob("mc_[0-9][0-9][0-9][0-9][0-9].mat")):
        saved, total = completion(path)
        if total != 6 * args.snr_count:
            raise ValueError(f"SNR-count mismatch: {path}")
        rows.append({"file": path.name, "saved": saved, "total": total})
    result = {"saved_cases": sum(r["saved"] for r in rows),
                      "total_cases": args.mc_total * 6 * args.snr_count,
                      "complete_mc": sum(r["saved"] == r["total"] for r in rows),
                      "mc_total": args.mc_total, "samples": rows}
    if args.summary:
        print(f'Saved cases: {result["saved_cases"]}/{result["total_cases"]}; '
              f'complete MC: {result["complete_mc"]}/{result["mc_total"]}')
    else:
        print(json.dumps(result, indent=2))
