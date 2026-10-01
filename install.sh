#!/bin/zsh
# Installs / removes the shim inside CrossOver's D3DMetal. Quit the game first.
#   ./install.sh install | uninstall | status
HERE=${0:A:h}
CX=${CROSSOVER:-/Applications/CrossOver.app}/Contents/SharedSupport/CrossOver
RES=$CX/lib64/apple_gptk/external/D3DMetal.framework/Versions/A/Resources
BK=$HERE/build/libmetalirconverter.dylib.stock

is_shim() { otool -L "$RES/libmetalirconverter.dylib" 2>/dev/null | grep -q libmetalirconverter_real }
running() { pgrep -f 'AceCombat8.exe' >/dev/null }

case "${1:-status}" in
  install)
    [[ -f $HERE/build/libmetalirconverter.dylib ]] || { print "Run ./build.sh first."; exit 1 }
    running && { print "The game is running. Quit it first."; exit 1 }
    if ! is_shim; then cp -p "$RES/libmetalirconverter.dylib" "$BK" || exit 1; fi
    cp "$HERE/build/libmetalirconverter_real.dylib" "$RES/libmetalirconverter_real.dylib" &&
    cp "$HERE/build/libmetalirconverter.dylib" "$RES/libmetalirconverter.dylib" &&
    print "Installed. Start the game; ~/Library/Logs/ac8-d3dmetal-shim.log should gain a 'substituted' line." ;;
  uninstall)
    is_shim || { print "Not installed."; exit 0 }
    running && { print "The game is running. Quit it first."; exit 1 }
    [[ -f $BK ]] || { print "Stock converter backup missing ($BK). Reinstall CrossOver to restore it."; exit 1 }
    cp -p "$BK" "$RES/libmetalirconverter.dylib" && rm -f "$RES/libmetalirconverter_real.dylib" &&
    print "Stock converter restored." ;;
  status)
    is_shim && print "Shim installed." || print "Stock converter (shim not installed)." ;;
  *) print "usage: $0 install|uninstall|status"; exit 1 ;;
esac
