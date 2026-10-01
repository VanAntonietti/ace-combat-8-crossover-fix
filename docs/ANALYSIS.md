# Analysis: black gameplay in ACE COMBAT 8 under D3DMetal

## Summary
Menus, hangar and character creator render correctly. In missions and cutscenes the 3D scene
is black: only the HUD, the pilot portrait and the game's self-lit canopy glints are visible.
D3DMetal fails to compile one compute shader of the game's custom sky/cloud renderer because
it uses 64-bit floating point. Without that shader the sky, atmosphere and all sun/sky lighting
stay at zero.

## Environment
- Game: ACE COMBAT 8: WINGS OF THEVE, Steam app 2288340, build 25201480
- Engine: Unreal Engine 5.4.3 (customized), DirectX 12 only, Shader Model 6.6
- CrossOver 26.3.0.39832, D3DMetal 3.0, MSync on
- Apple M5 Pro (20-core GPU), 64 GB, macOS 27.0 (26A428)

## Evidence
macOS unified log, once per game launch, during startup shader precompilation:

    [MetalIRConverter:] FP64Usage : Unhandled FP64 usage
    [D3DMetal:] Failed to compile stage Compute - error:19, <private>

Query: /usr/bin/log show --last 10m --predicate 'senderImagePath CONTAINS[c] "D3DMetal"'

Scanning the original DXIL kept in D3DMetal's bytecode cache
($(getconf DARWIN_USER_CACHE_DIR)d3dm/AceCombat8.exe/shaders.cache/.../bytecode_cache.bin):
- 15,577 shader containers, 8,170 of them compute shaders
- exactly one container has the "doubles" feature flag: SFI0 = 0xC021
  (double-precision floats, 11.1 double extensions, wave ops, 64-bit integers)
- its entry point is TraceTilesClassifyCS, part of the game's "Cloudly" sky/atmosphere/cloud
  system (other Cloudly compute passes: SkyTraceCS, CoarseTraceCS, CompositeAtmosphereCS,
  ShadowTraceCS). It classifies screen tiles and feeds the sky and cloud trace passes.
- only one variant of this shader exists, so no quality setting selects a working one.

Also logged on every launch, believed harmless (unused alternate variants of stock UE shaders):

    28x [MetalIRConverter:] UnsupportedWaveSize : Wave size is not supported. Must be 32.
    28x [D3DMetal:] Failed to compile stage Compute - error:6
     5x [MetalIRConverter:] Compute quad ops in SM6.6 are only supported for 1D threadgroup size

## Ruled out (each tested in a mission, no change)
- Ray tracing hidden from the game (D3DM_SUPPORT_DXR=0)
- Unreal app detection (D3DM_EXE_OVERRIDE=AceCombat8-Win64-Shipping.exe; the exe name does not
  end in Win64-Shipping.exe, so D3DMetal treats the game as an unknown app)
- D3DM_FLUSH_POS_INF_TO_NAN=0 with a rebuilt shader cache
- Engine cvars via a locked user Engine.ini (the game honors it; it deletes the file at launch
  unless it is immutable): Lumen and RT effects off, stock sky/cloud/fog off, manual exposure,
  wave-size 32 / wave ops off, r.SkyLight.QGames.CloudAOAttenuation*=0,
  r.Cloudly.ScalabilityBias.AllHighResTiles=1
- In-game settings: all quality levels, upscalers, HDR on/off

## Root cause in the shader source, and a verified workaround
The shader's embedded source (ILDB part, dx.source.contents) has this line:

    bLowResTile = (WaveActiveSum(near_tile || no_clouds_tile) > WaveActiveSum(1) * 0.3) && ...

`WaveActiveSum(1)` is int64 and `0.3` is a double literal, producing `sitofp i64 -> double`,
`fmul double`, `fptrunc`. Recompiling with `float(WaveActiveSum(1u)) * 0.3f` (same dxc arguments)
gives a shader with no FP64/int64 and identical bindings. Substituting that container at
IRObjectCreateFromDXIL makes the converter succeed, and cutscenes and missions render correctly
(verified on the setup above). Calling the converter directly: original fails with error 19,
patched compiles.

## What would fix it properly
- Developer: change the literal to `0.3f` (and `1u`) in `TraceTilesClassifyCS`.
- Apple / CodeWeavers: FP64 support or emulation in the Metal shader converter, or a per-game
  workaround in D3DMetal/CrossOver.

## Other notes
- At launch the game warns that the "AMD Compatibility Mode" driver 30.0.15.1233 is outdated
  (recommended 26.3.1). Cosmetic; unrelated to the black scene.
- Metal API validation reports acceleration-structure scratch buffer size errors and 4x4
  buffer-to-texture copies into 2x2 and 1x1 mips. 
