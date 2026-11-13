import argparse
import json
import os
from pathlib import Path
import tomllib
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname
from zipfile import ZIP_DEFLATED, ZipFile


def add_notices(payload, directory, destination):
    for path in sorted(directory.iterdir()):
        prefix = path.name.upper().split(".", 1)[0].split("-", 1)[0]
        if path.is_file() and prefix in {"LICENSE", "LICENCE", "COPYING", "COPYRIGHT", "NOTICE"}:
            payload[f"{destination}/{path.name}"] = path


def package(root, rust_exe, native_dir, output):
    project = root / "gpui-prototype"
    payload = {
        "purelive-gpui.exe": rust_exe,
        "purelive-platforms.exe": root / "dist/purelive-platforms.exe",
        "README.md": project / "README.md",
        "LICENSE": root / "LICENSE",
        "THIRD_PARTY.md": root / "THIRD_PARTY.md",
    }
    for name in ("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"):
        payload[name] = native_dir / name
    # The sherpa-onnx build copies its own runtime DLLs next to the executable.
    for name in ("onnxruntime.dll", "onnxruntime_providers_shared.dll", "sherpa-onnx-c-api.dll", "sherpa-onnx-cxx-api.dll"):
        payload[name] = rust_exe.parent / name
    for path in sorted((root / "licenses/onnxruntime").iterdir()):
        payload[f"licenses/onnxruntime/{path.name}"] = path

    cargo_home = Path(os.environ.get("CARGO_HOME", Path.home() / ".cargo"))
    registry = cargo_home / "registry/src"
    lock = tomllib.loads((project / "Cargo.lock").read_text(encoding="utf-8"))
    for crate in lock["package"]:
        if not crate.get("source", "").startswith("registry+"):
            continue
        versioned = f"{crate['name']}-{crate['version']}"
        for directory in sorted(registry.glob(f"*/{versioned}")):
            add_notices(payload, directory, f"licenses/rust/{versioned}")
            break

    config = root / ".dart_tool/package_config.json"
    packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
    for entry in packages:
        uri = urlparse(urljoin(config.as_uri(), entry["rootUri"]))
        if uri.scheme == "file":
            directory = Path(url2pathname(uri.path))
            add_notices(payload, directory, f"licenses/dart/{entry['name']}")

    for path in payload.values():
        if not path.is_file():
            raise FileNotFoundError(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    temp = output.with_suffix(".tmp")
    with ZipFile(temp, "w", ZIP_DEFLATED, strict_timestamps=False) as archive:
        for name, path in sorted(payload.items()):
            archive.write(path, name)
    with ZipFile(temp) as archive:
        if archive.testzip() is not None or set(archive.namelist()) != set(payload):
            raise RuntimeError("ZIP validation failed")
    temp.replace(output)


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="Package the Windows x64 handheld build.")
    parser.add_argument("--native-dir", type=Path, required=True)
    parser.add_argument("--rust-exe", type=Path, default=root / "gpui-prototype/target/release/purelive-gpui.exe")
    parser.add_argument("--output", type=Path, default=root / "dist/PureLive-Rust-Handheld-Windows-x64.zip")
    args = parser.parse_args()
    package(root, args.rust_exe, args.native_dir, args.output)
