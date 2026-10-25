---
name: skyrim-audio
description: Handle Skyrim audio files including FUZ, XWM, and WAV formats. Use when the user wants to inspect audio, extract voice files, create FUZ files, or convert audio formats.
---

# Skyrim Audio Module

Inspect, extract, convert, and package Skyrim SE/AE audio files (`.fuz`, `.xwm`, `.wav`, `.lip`) using **Skyrim Forge**, **houseCARL** BSA tools (`housecarl_bsa_list`, `housecarl_bsa_extract`), and deterministic binary/audio utilities. For dialogue record wiring (`DIAL`/`INFO`, `NAM1` response text, voice-type folders, `.seq` generation), pair this skill with `skyrim-voiced-dialogue`.

## Skyrim Audio Formats

| Format | Extension | Purpose |
|--------|-----------|---------|
| **FUZ** | `.fuz` | Combined voice container (`FUZE` header + optional `.lip` lip-sync payload + `.xwm` audio payload) |
| **XWM** | `.xwm` | Compressed audio (`XWMA` RIFF container; standard for voice lines, music, and long FX) |
| **WAV** | `.wav` | Uncompressed PCM audio (`44100 Hz`, `16-bit`, mono for voice / 3D positional SFX, stereo for UI / music) |
| **LIP** | `.lip` | FaceFX phoneme/viseme lip-sync animation track generated from mono PCM `.wav` + response text |

---

## FUZ Container Binary Specification

`FUZ` files have a simple deterministic binary header (`little-endian`), making inspection, extraction, and packing exact in Python or PowerShell without external proprietary wrappers:

```text
Offset  Size      Type       Description
0x00    4 bytes   char[4]    Magic signature: ASCII "FUZE" (0x455A5546)
0x04    4 bytes   uint32     Version: always 1 (0x00000001)
0x08    4 bytes   uint32     LIP payload size in bytes (N; 0 if no lip sync)
0x0C    N bytes   uint8[N]   Raw .lip file bytes
0x0C+N  ...       uint8[]    Raw .xwm (or .wav) audio bytes to EOF
```

### Inspect / Unpack / Pack `.fuz` (Shared Python One-Liner)

Use the shared user `python` (`UABS_PYTHON` or `python` on PATH) to inspect, split, or assemble `.fuz` containers deterministically:

```python
import struct, pathlib

def unpack_fuz(fuz_path: str, out_dir: str) -> dict:
    data = pathlib.Path(fuz_path).read_bytes()
    magic, version, lip_size = struct.unpack_from("<4sII", data, 0)
    assert magic == b"FUZE" and version == 1, f"Invalid FUZ header: {magic!r} v{version}"
    stem = pathlib.Path(out_dir) / pathlib.Path(fuz_path).stem
    stem.parent.mkdir(parents=True, exist_ok=True)
    lip_bytes = data[12 : 12 + lip_size]
    xwm_bytes = data[12 + lip_size :]
    if lip_size:
        stem.with_suffix(".lip").write_bytes(lip_bytes)
    stem.with_suffix(".xwm").write_bytes(xwm_bytes)
    return {"version": version, "lip_size": lip_size, "audio_size": len(xwm_bytes)}

def pack_fuz(xwm_path: str, out_fuz_path: str, lip_path: str | None = None) -> None:
    lip_bytes = pathlib.Path(lip_path).read_bytes() if lip_path else b""
    xwm_bytes = pathlib.Path(xwm_path).read_bytes()
    header = struct.pack("<4sII", b"FUZE", 1, len(lip_bytes))
    out = pathlib.Path(out_fuz_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(header + lip_bytes + xwm_bytes)
```

---

## WAV ↔ XWM Conversion and LIP Generation

1. **Extracting Voice Assets from BSAs**:
   - Use `housecarl_bsa_list` and `housecarl_bsa_extract` (or `Skyrim Forge` / `bsarch.exe`) to list and extract `.fuz`, `.xwm`, and `.wav` files from `Skyrim - Voices_en0.bsa` or mod BSAs into your workspace.
2. **WAV ↔ XWM Conversion**:
   - Resolve `xWMAEncode.exe` (Creation Kit / DirectX SDK) or `ffmpeg` via `tool-discovery`.
   - With `ffmpeg` (when installed on PATH):
     - `.xwm` → `.wav`: `ffmpeg -y -i input.xwm -ar 44100 -ac 1 -c:a pcm_s16le output.wav`
     - `.wav` → `.xwm`: `xWMAEncode.exe input.wav output.xwm` (or `ffmpeg -y -i input.wav -ar 44100 -ac 1 -b:a 48k output.xwm`)
3. **LIP Sync Generation**:
   - Requires Creation Kit (`CreationKit.exe -GenerateLip:<wav> "<text>"`) or FaceFXWrapper / LipGen community tools discovered under the user's Skyrim tools root.
   - Input WAV must be **uncompressed PCM, 16-bit, mono, 44100 Hz**.

---

## Voice File Path Convention

Skyrim resolves dialogue audio strictly by defining master filename (not override plugin), voice-type EditorID, topic/INFO FormID, and response index:

```text
Data/Sound/Voice/<DefiningPlugin.esp>/<VoiceTypeEditorID>/<TopicPrefix>_<INFO_FormID_8Hex>_<ResponseIndex>.fuz
```

- **`<DefiningPlugin.esp>`**: The plugin that originally defines the `INFO` record. For light plugins (`FE xxx`), the 8-digit hex FormID in the voice filename uses `00000xxx` (strip master index bits).
- **`<VoiceTypeEditorID>`**: Exact EditorID of the `VTYP` record assigned to the speaker NPC or quest alias condition.
- **`<ResponseIndex>`**: 1-based index of the `TRDT`/`NAM1` response item inside the `INFO` record (`_1`, `_2`, etc.).

## Safety Rules

- Never write directly into `Data\Sound\Voice`; build voice trees inside the mod's versioned workspace (`skyrim-versioned-workspace`).
- When packing voice `.fuz` files into a `.bsa` with `bsarch`, **do not enable BSA compression** on archives containing `.fuz` or `.xwm` files — compressed voice/sound BSAs cause audio stutter, static, or instant CTDs in Skyrim SE/AE.
