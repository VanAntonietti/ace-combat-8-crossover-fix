#!/usr/bin/env python3
"""Find ACE COMBAT 8's FP64 compute shader in D3DMetal's bytecode cache.

D3DMetal keeps every DXIL container the game has handed it in
  $(getconf DARWIN_USER_CACHE_DIR)d3dm/AceCombat8.exe/shaders.cache/*/bytecode_cache.bin
This scans that file for DXBC containers, and writes out the compute shader(s) whose
feature flags (SFI0) include double-precision floats.

usage: extract_shader.py <out_dir> [cache_file ...]
"""
import glob, mmap, os, struct, subprocess, sys

DOUBLES = 0x1
COMPUTE = 5


def containers(m):
    n, pos = len(m), 0
    while True:
        i = m.find(b"DXBC", pos)
        if i < 0:
            return
        pos = i + 4
        if i + 32 > n:
            return
        ver, total, nparts = struct.unpack_from("<III", m, i + 20)
        if ver != 1 or total < 32 or total > (64 << 20) or nparts > 64 or i + total > n:
            continue
        flags, kind, ok = 0, None, True
        for o in struct.unpack_from("<%dI" % nparts, m, i + 32):
            if o + 8 > total:
                ok = False
                break
            fourcc = m[i + o:i + o + 4]
            size = struct.unpack_from("<I", m, i + o + 4)[0]
            if fourcc == b"SFI0" and size >= 8:
                flags = struct.unpack_from("<Q", m, i + o + 8)[0]
            elif fourcc == b"DXIL":
                kind = (struct.unpack_from("<I", m, i + o + 8)[0] >> 16) & 0xFFFF
        if ok and kind is not None:
            yield i, total, kind, flags
            pos = i + total


def main():
    out_dir = sys.argv[1]
    files = sys.argv[2:]
    if not files:
        cache = subprocess.check_output(["getconf", "DARWIN_USER_CACHE_DIR"]).decode().strip()
        files = glob.glob(os.path.join(cache, "d3dm", "AceCombat8.exe", "shaders.cache", "*", "bytecode_cache.bin"))
    if not files:
        sys.exit("No D3DMetal shader cache for AceCombat8.exe found. Launch the game once (to the main menu), quit, and retry.")
    os.makedirs(out_dir, exist_ok=True)
    found, seen, total_cs = [], set(), 0
    for path in files:
        with open(path, "rb") as f:
            m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
            for off, size, kind, flags in containers(m):
                if kind != COMPUTE:
                    continue
                total_cs += 1
                if flags & DOUBLES:
                    blob = m[off:off + size]
                    digest = blob[4:20].hex()
                    if digest in seen:
                        continue
                    seen.add(digest)
                    name = os.path.join(out_dir, "fp64_%d.dxbc" % len(found))
                    with open(name, "wb") as o:
                        o.write(blob)
                    found.append(name)
    print("scanned %d compute shaders, %d use FP64" % (total_cs, len(found)))
    for name in found:
        print(name)
    if not found:
        sys.exit("No FP64 compute shader in the cache. Either the game has not been launched yet, "
                 "or the game/CrossOver has been updated and no longer needs this fix.")


if __name__ == "__main__":
    main()
