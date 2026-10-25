---
name: skyrim-nif
description: Read and manipulate NIF 3D mesh files. Use when the user wants to inspect meshes, find texture paths, rewrite texture paths, rename node/block names, inspect or fix eye shader flags, verify roundtrip safety, restore backups, scale models, or troubleshoot invisible items.
---

# Skyrim NIF Module

Read and manipulate Skyrim SE/AE NIF (`NetImmerse Format`, version `20.2.0.7`, BS version `100`) 3D mesh files using **houseCARL 2.1.1** (`housecarl_nif_inspect`, `housecarl_nif_set`) and **Skyrim Forge** (`dmscan`, `NIF Optimizer`, `NIFAnalyzer`, `NifSkope`).

## Tool Routing

1. **houseCARL MCP (`housecarl_nif_inspect`, `housecarl_nif_set`)**:
   - Inspects NIF blocks, node hierarchy, `BSLightingShaderProperty` / `BSEffectShaderProperty` flags (`ShaderFlags1`, `ShaderFlags2`), `BSShaderTextureSet` slots, string table entries, and FaceGen eye/tint flags directly across VFS or mod folders.
   - Modifies texture paths, shader flags, alpha/parallax/PBR properties, node transforms, and string table entries safely with backup preservation.
   - Note: `housecarl_nif_set` is excluded in the `Lean` and `ReadOnly` Hermes toolsets by default to save schema bytes; call it via `toolbox` or enable the `Full` toolset when mutating NIFs via MCP.
2. **Skyrim Forge CLI (`forge`)**:
   - Runs `dmscan` / `NIFAnalyzer` for mesh validation, `SSE NIF Optimizer` / `Cathedral Assets Optimizer` for LE-to-SE conversion and headpart/BSTriShape optimization, and `bsarch` for BSA extraction/packing.
3. **Blender + PyNifly / NifTools** or **NifSkope**:
   - Required for creating new geometry from scratch, editing vertices/UVs, or re-rigging skin weights.

---

## Primary Operations

### 1. Inspect NIF Structure, Textures, and Shaders
Use `housecarl_nif_inspect` on a file path or VFS-resolved mesh path (`meshes\...`):
- Lists block indices, block types (`BSFadeNode`, `BSTriShape`, `BSDynamicTriShape`, `BSLightingShaderProperty`, `BSShaderTextureSet`, `NiAlphaProperty`), vertex/triangle counts, and bounding spheres.
- Displays all 9 texture slots (`0..8`) in each `BSShaderTextureSet`.
- Reports `ShaderFlags1` and `ShaderFlags2` bitmasks and decoded flag names, highlighting FaceGen eye-environment mapping bugs (`Eye_Environment_Mapping` vs `Environment_Mapping`).

### 2. Rewrite Texture Paths or Shader Flags
Use `housecarl_nif_set` (or a targeted Python/NifSkope pass in an owned workspace):
- **Texture replacement**: Update `BSShaderTextureSet` slots (`0` Diffuse, `1` Normal, `2` Glow/Skin/Soft lighting, `3` Parallax/Height, `4` Cubemap, `5` EnvMask, `6` Subsurface/Inner layer, `7` Backlight/Specular).
- **Node/String renaming**: Rename `NiNode` / `BSTriShape` names in the NIF header string table (e.g., when cloning FaceGen `BSFaceGenNiNode` headparts).
- **Shader flag fixes**:
  - **Eye ghosting bug** in FaceGen NIFs (`Meshes\actors\character\FaceGenData\FaceGeom\<Plugin>\<FormID>.nif`): Clear `Eye_Environment_Mapping` (SF1 bit 17) on non-eye blocks or fix `Environment_Mapping` (SF1 bit 7) + `Eye_Environment_Mapping` pairing on eye meshes.
  - **FaceTint / Skin Tint**: Ensure `FaceGen_RGB_Tint` (SF1 bit 29) and `Soft_Lighting` (SF2 bit 24) match the `BSLightingShaderProperty` shader type (`Face_Tint` = 6 vs `Skin_Tint` = 5).

---

## Texture Slot Reference (`BSShaderTextureSet`)

| Slot | Typical Suffix | Standard Shader | Skin / FaceGen Shader | PBR (Community Shaders) |
|------|----------------|-----------------|-----------------------|-------------------------|
| 0 | `_d` / none | Diffuse (Albedo + Alpha) | Diffuse | BaseColor |
| 1 | `_n` / `_msn` | Tangent-space Normal (+ Specular in alpha) | Model-space Normal (`_msn`) | Tangent Normal |
| 2 | `_g` / `_sk` | Glow / Emissive | Subsurface Skin Tint (`_sk`) | Emissive |
| 3 | `_p` | Parallax Heightmap | Detail / Dirt map | Height / Displacement |
| 4 | `_e` | Environment Cube Map | Unused | Unused |
| 5 | `_m` / `_em` | Environment Mask | Unused | Unused |
| 6 | `_s` | Inner Layer / Multilayer | FaceTint (`actors\character\FaceGenData\FaceTint\...`) | RMAOS (Roughness, Metallic, AO, Specular) |
| 7 | `_b` / `_s` | Backlight | Specular (`_s`) | Subsurface / Fuzz |

---

## Troubleshooting Invisible or Purple Items

1. **Purple / violet surface in-game**:
   - Missing `.dds` texture in `BSShaderTextureSet` slot 0 or slot 1, or corrupt BC7/DXT header.
   - Inspect texture paths with `housecarl_nif_inspect` and verify existence across the VFS with `housecarl_asset_status` or `housecarl_bsa_list`.
2. **Completely invisible mesh in-game**:
   - Wrong `Biped Body Template` (`BOD2`) slot mask in the `BSDismemberSkinInstance` partitions vs the plugin's `ARMA`/`ARMO` record (audit with `biped-slot-reference`).
   - Old Skyrim LE `NiTriShapeData` / `NiSkinPartition` format not converted to SE `BSTriShape` (convert with SSE NIF Optimizer).
   - Missing `Skinned` flag (`SLSF1_Skinned`) on `BSLightingShaderProperty` for rigged armor/clothing, or `Skinned` left enabled on a static world/inventory ground mesh (`_gnd.nif`).
   - Corrupt bounding sphere (radius `0` or `NaN` center) causing camera frustum culling.

## Safety Rules

- Never overwrite meshes inside live game `Data` or mod-manager staging directly; work in the mod's versioned workspace (`skyrim-versioned-workspace`).
- Keep `.nif.bak` backups before batch shader or texture-path edits.
- Verify that every modified NIF re-parses cleanly and preserves block count and partition count before packaging.
