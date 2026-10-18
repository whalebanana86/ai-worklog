"""아이콘을 작게 만든다.  사용: python3 scripts/compress_icon.py <AppIcon.iconset 폴더> <만들 .icns>

1) PNG 를 256색 팔레트로 줄인다 (투명도 유지). 아이콘은 단색 면과 부드러운 그라데이션뿐이라 눈으로 차이가 거의 없다.
2) iconutil 은 줄인 PNG 를 다시 큰 형식으로 바꿔 넣어서, iconutil 이 만든 icns 의 항목 종류는 그대로 두고
   PNG 내용만 줄인 것으로 바꿔 다시 묶는다.
PIL(Pillow)이 없으면 iconutil 결과를 그대로 쓴다.
"""
import struct
import subprocess
import sys
from pathlib import Path

folder, out = Path(sys.argv[1]), Path(sys.argv[2])
subprocess.run(["iconutil", "-c", "icns", str(folder), "-o", str(out)], check=True)

try:
    from PIL import Image
except ImportError:
    print("PIL 이 없어 아이콘 압축을 건너뜀")
    sys.exit(0)

# icns 항목 종류 → iconset 파일 이름
FILES = {
    "ic07": "icon_128x128.png", "ic08": "icon_256x256.png", "ic09": "icon_512x512.png",
    "ic10": "icon_512x512@2x.png", "ic11": "icon_16x16@2x.png", "ic12": "icon_32x32@2x.png",
    "ic13": "icon_128x128@2x.png", "ic14": "icon_256x256@2x.png",
}

def small_png(path: Path) -> bytes:
    img = Image.open(path).convert("RGBA")
    tmp = path.with_suffix(".small.png")
    img.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save(tmp, optimize=True)
    data = tmp.read_bytes()
    tmp.unlink()
    return data

before = out.stat().st_size
data = out.read_bytes()
entries, i = [], 8
while i < len(data):
    kind = data[i:i + 4].decode("latin1")
    length = struct.unpack(">I", data[i + 4:i + 8])[0]
    body = data[i + 8:i + length]
    if kind in FILES and body[:4] == b"\x89PNG":
        smaller = small_png(folder / FILES[kind])
        if len(smaller) < len(body):
            body = smaller
    entries.append((kind, body))
    i += length

packed = b"".join(k.encode("latin1") + struct.pack(">I", len(b) + 8) + b for k, b in entries)
out.write_bytes(b"icns" + struct.pack(">I", len(packed) + 8) + packed)
print(f"아이콘 {before // 1024}KB → {out.stat().st_size // 1024}KB")
