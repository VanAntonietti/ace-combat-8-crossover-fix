#!/usr/bin/env python3
"""Pull the embedded HLSL out of a `dxc -dumpbin` listing, apply the one-token FP64 fix,
and emit the shim's headers.

usage:
  patch_shader.py source <listing.txt> <out.hlsl>      extract + patch the source
  patch_shader.py headers <orig.dxbc> <fixed.dxbc> <out_dir>   write orig_ids.h / fixed_blob.h
"""
import re, struct, sys

ENTRY = "TraceTilesClassifyCS"
OLD = b"WaveActiveSum(1) * 0.3)"
NEW = b"float(WaveActiveSum(1u)) * 0.3f)"


def unescape(s):
    return re.sub(rb"\\([0-9A-Fa-f]{2})", lambda m: bytes([int(m.group(1), 16)]), s.encode("latin-1"))


def source(listing, out):
    t = open(listing, encoding="latin-1").read()
    if "define void @%s()" % ENTRY not in t:
        sys.exit("This FP64 shader is not %s; the game has changed and this fix does not apply as-is." % ENTRY)
    m = re.search(r"^!dx\.source\.contents = !\{!(\d+)", t, re.M)
    if not m:
        sys.exit("The shader has no embedded source (dx.source.contents); cannot rebuild it.")
    node = re.search(r'^!%s = !\{!"((?:[^"\\]|\\.)*)", !"((?:[^"\\]|\\.)*)"\}' % m.group(1), t, re.M)
    src = unescape(node.group(2))
    if src.count(OLD) != 1:
        sys.exit("Expected exactly one '%s' in the shader source, found %d. The shader has changed."
                 % (OLD.decode(), src.count(OLD)))
    open(out, "wb").write(src.replace(OLD, NEW))
    print("patched source written: %s (%d lines)" % (out, src.count(b"\n")))


def hash_part(b):
    nparts = struct.unpack_from("<I", b, 28)[0]
    for k in range(nparts):
        o = struct.unpack_from("<I", b, 32 + 4 * k)[0]
        if b[o:o + 4] == b"HASH":
            return b[o + 12:o + 28]
    return bytes(16)


def sfi0(b):
    nparts = struct.unpack_from("<I", b, 28)[0]
    for k in range(nparts):
        o = struct.unpack_from("<I", b, 32 + 4 * k)[0]
        if b[o:o + 4] == b"SFI0":
            return struct.unpack_from("<Q", b, o + 8)[0]
    return 0


def carray(b):
    return ",".join("0x%02x" % x for x in b)


def headers(orig, fixed, out_dir):
    o, f = open(orig, "rb").read(), open(fixed, "rb").read()
    if sfi0(f) & 1:
        sys.exit("The recompiled shader still uses FP64; refusing to continue.")
    with open(out_dir + "/orig_ids.h", "w") as h:
        h.write("static const unsigned char kOrigDigest[16]={%s};\n" % carray(o[4:20]))
        h.write("static const unsigned char kOrigHash[16]={%s};\n" % carray(hash_part(o)))
        h.write("static const unsigned long kOrigSize=%d;\n" % len(o))
    with open(out_dir + "/fixed_blob.h", "w") as h:
        h.write("static const unsigned char kFixedShader[]={%s};\n" % carray(f))
        h.write("static const unsigned long kFixedShaderLen=%d;\n" % len(f))
    print("original: %d bytes, digest %s; fixed: %d bytes, no FP64" % (len(o), o[4:20].hex(), len(f)))


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "source":
        source(sys.argv[2], sys.argv[3])
    elif len(sys.argv) >= 5 and sys.argv[1] == "headers":
        headers(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        sys.exit(__doc__)
