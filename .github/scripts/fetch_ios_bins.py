import gzip
import io
import lzma
import os
import shutil
import subprocess
import tarfile
import traceback
from pathlib import Path

import zstandard as zstd


BASE_URL = "https://strap.palera.in"
REPO_PATH = f"{BASE_URL}/dists/iphoneos-arm64/1900/main/binary-iphoneos-arm/Packages"
PACKAGES = ("dpkg", "zstd", "libzstd1", "liblzma5")


def run_curl(url: str, destination: Path) -> None:
    subprocess.run(
        [
            "curl",
            "-fsSL",
            "--retry",
            "3",
            "--retry-all-errors",
            url,
            "-o",
            str(destination),
        ],
        check=True,
    )


def parse_packages_index(contents: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for block in contents.strip().split("\n\n"):
        fields = {}
        for line in block.splitlines():
            if ": " not in line:
                continue
            key, value = line.split(": ", 1)
            fields[key] = value
        name = fields.get("Package")
        path = fields.get("Filename")
        if name in PACKAGES and path and name not in result:
            result[name] = path
    return result


def iter_ar_members(data: bytes):
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("Not an ar archive")

    offset = 8
    while offset + 60 <= len(data):
        header = data[offset : offset + 60]
        name = header[0:16].decode("utf-8", errors="replace").strip()
        size = int(header[48:58].decode("ascii").strip())
        offset += 60
        payload = data[offset : offset + size]
        yield name.rstrip("/"), payload
        offset += size + (size % 2)


def extract_data_member(deb_bytes: bytes, output_dir: Path) -> None:
    data_member = None
    for name, payload in iter_ar_members(deb_bytes):
        if name.startswith("data.tar"):
            data_member = (name, payload)
            break

    if data_member is None:
        raise RuntimeError("Missing data.tar member")

    name, payload = data_member
    if name.endswith(".zst"):
        source = io.BytesIO(payload)
        target = io.BytesIO()
        zstd.ZstdDecompressor().copy_stream(source, target)
        payload = target.getvalue()
    elif name.endswith(".xz"):
        payload = lzma.decompress(payload)
    elif name.endswith(".gz"):
        payload = gzip.decompress(payload)

    with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
        archive.extractall(output_dir)


def copy_match(pattern: str, destination: Path) -> None:
    matches = sorted(Path(".").glob(pattern))
    if not matches:
        raise FileNotFoundError(f"No files matched {pattern}")

    for src in matches:
        dst = destination / src.name
        if dst.exists() or dst.is_symlink():
            if dst.is_dir() and not dst.is_symlink():
                shutil.rmtree(dst)
            else:
                dst.unlink()

        if src.is_symlink():
            os.symlink(os.readlink(src), dst)
        else:
            shutil.copy2(src, dst)


def main() -> None:
    workspace = Path.cwd()
    ios_bins = workspace / "ios_bins"
    if ios_bins.exists():
        shutil.rmtree(ios_bins)
    ios_bins.mkdir()

    index_path = ios_bins / "Packages"
    run_curl(REPO_PATH, index_path)
    index = index_path.read_text(encoding="utf-8", errors="replace")
    package_paths = parse_packages_index(index)

    missing = [pkg for pkg in PACKAGES if pkg not in package_paths]
    if missing:
        raise RuntimeError(f"Failed to resolve packages: {', '.join(missing)}")

    os.chdir(ios_bins)
    for pkg in PACKAGES:
        deb_path = Path(f"{pkg}.deb")
        print(f"Downloading {pkg} from {package_paths[pkg]}")
        run_curl(f"{BASE_URL}/{package_paths[pkg]}", deb_path)
        deb_bytes = deb_path.read_bytes()

        extract_dir = Path("extracted") / pkg
        extract_dir.mkdir(parents=True, exist_ok=True)
        extract_data_member(deb_bytes, extract_dir)

    copy_match("extracted/*/usr/bin/dpkg-deb", Path("."))
    copy_match("extracted/*/usr/bin/zstd", Path("."))
    copy_match("extracted/*/usr/lib/libzstd*.dylib", Path("."))
    copy_match("extracted/*/usr/lib/liblzma*.dylib", Path("."))

    for path in (
        Path("dpkg-deb"),
        Path("zstd"),
        *sorted(Path(".").glob("libzstd*.dylib")),
        *sorted(Path(".").glob("liblzma*.dylib")),
    ):
        print(path.name)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        traceback.print_exc()
        print(f"::error::{exc}")
        raise
