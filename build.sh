#!/bin/zsh
# Builds the ACE COMBAT 8 shader-converter shim from your own installed files.
# Nothing from the game, Apple or Microsoft is shipped in this repository.
#
#   BOTTLE=Steam ./build.sh        (BOTTLE = name of the CrossOver bottle the game runs in)
set -e
HERE=${0:A:h}
B=$HERE/build
BOTTLE=${BOTTLE:-Steam}
CX=${CROSSOVER:-/Applications/CrossOver.app}/Contents/SharedSupport/CrossOver
WINE=$CX/bin/wine
RES=$CX/lib64/apple_gptk/external/D3DMetal.framework/Versions/A/Resources
DXC_URL=https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.9.2609/dxc_2026_09_29.zip

die() { print -u2 -- "error: $*"; exit 1 }
[[ -x $WINE ]] || die "CrossOver not found at ${CROSSOVER:-/Applications/CrossOver.app} (set CROSSOVER=/path/to/CrossOver.app)"
[[ -f $RES/libmetalirconverter.dylib ]] || die "D3DMetal's shader converter not found inside CrossOver"
[[ -d "$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE" ]] || die "no CrossOver bottle named '$BOTTLE' (set BOTTLE=...)"
for t in clang++ python3 curl codesign install_name_tool; do command -v $t >/dev/null || die "$t is missing (install Xcode Command Line Tools: xcode-select --install)"; done
mkdir -p $B/dxc

print "== 1/5 locating the FP64 shader in D3DMetal's cache"
python3 $HERE/tools/extract_shader.py $B
[[ -f $B/fp64_1.dxbc ]] && die "more than one FP64 shader found; this build only knows how to fix TraceTilesClassifyCS"
cp $B/fp64_0.dxbc $B/original.dxbc

print "== 2/5 fetching Microsoft's DirectX Shader Compiler (runs through CrossOver)"
if [[ ! -f $B/dxc/dxc.exe ]]; then
  curl -fsSL -o $B/dxc/dxc.zip $DXC_URL
  python3 - $B/dxc <<'PY'
import os, sys, zipfile
d = sys.argv[1]
z = zipfile.ZipFile(os.path.join(d, "dxc.zip"))
for n in z.namelist():
    p = n.replace("\\", "/")
    if p.startswith("bin/x64/") and not p.endswith("/"):
        open(os.path.join(d, os.path.basename(p)), "wb").write(z.read(n))
PY
fi
dxc() {  # run dxc.exe inside the bottle with build/ as the working directory
  local exe="Z:${${B}//\//\\}\\dxc\\dxc.exe"
  ( cd $B && "$WINE" --bottle "$BOTTLE" --no-update --workdir "$B" --cx-app "$exe" "$@" ) > $B/dxc.log 2>&1 || { cat $B/dxc.log; die "dxc failed"; }
}

print "== 3/5 extracting the shader's embedded source and recompiling without FP64"
rm -f $B/original.txt $B/fixed.dxbc
dxc -dumpbin original.dxbc -Fc original.txt
[[ -s $B/original.txt ]] || { cat $B/dxc.log; die "could not disassemble the shader"; }
python3 $HERE/tools/patch_shader.py source $B/original.txt $B/fixed.hlsl
# Same arguments the developer used (recorded in the shader), minus the debug-info ones.
dxc -HV 2021 -Zpr -O3 -WX -auto-binding-space 0 -Zsb -Wno-parentheses-equality -disable-lifetime-markers \
    -E TraceTilesClassifyCS -T cs_6_6 fixed.hlsl -Fo fixed.dxbc
[[ -s $B/fixed.dxbc ]] || { cat $B/dxc.log; die "recompiling the shader failed"; }
python3 $HERE/tools/patch_shader.py headers $B/original.dxbc $B/fixed.dxbc $B

print "== 4/5 building the shim"
cp $RES/libmetalirconverter.dylib $B/libmetalirconverter_real.dylib
if otool -L $B/libmetalirconverter_real.dylib | grep -q libmetalirconverter_real; then
  # The shim is already installed; take the pristine converter that install.sh kept beside it.
  [[ -f $RES/libmetalirconverter_real.dylib ]] || die "shim installed but real converter missing; run ./install.sh uninstall first"
  cp $RES/libmetalirconverter_real.dylib $B/libmetalirconverter_real.dylib
else
  install_name_tool -id @rpath/libmetalirconverter_real.dylib $B/libmetalirconverter_real.dylib 2>/dev/null
  codesign -f -s - $B/libmetalirconverter_real.dylib 2>/dev/null
fi
clang++ -arch x86_64 -std=c++17 -O2 -mmacosx-version-min=11.0 -w -dynamiclib -I$B $HERE/src/shim.cpp \
  -o $B/libmetalirconverter.dylib -install_name @rpath/libmetalirconverter.dylib \
  -compatibility_version 0 -current_version 0 \
  -Wl,-reexport_library,$B/libmetalirconverter_real.dylib -Wl,-rpath,@loader_path
codesign -f -s - $B/libmetalirconverter.dylib 2>/dev/null

print "== 5/5 testing against Apple's converter"
clang++ -arch x86_64 -std=c++17 -O1 -mmacosx-version-min=13.0 -w $HERE/src/shimtest.cpp -o $B/shimtest \
  -L$B -lmetalirconverter -Wl,-rpath,@loader_path
$B/shimtest $B/original.dxbc $B/libmetalirconverter_real.dylib || die "the shim did not make the shader compile"

print "\nBuild OK. Quit the game and Steam, then run: ./install.sh install"
