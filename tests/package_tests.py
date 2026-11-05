"""Validate loose-PNG icon declarations and installer behavior without iOS."""
from pathlib import Path
import io
import plistlib
import shlex
import struct
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def check_icons(read):
    info = plistlib.loads(read("Info.plist"))
    assert info["CFBundleIdentifier"] == "com.xsxs18.voidy"
    assert info["CFBundleShortVersionString"] == "1.0.4"
    for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
        icon = info[key]["CFBundlePrimaryIcon"]
        assert "CFBundleIconName" not in icon, "No asset catalog is shipped"
        assert "AppIcon60x60" in icon["CFBundleIconFiles"]
    expected = {"AppIcon60x60.png": 60, "AppIcon60x60@2x.png": 120,
                "AppIcon60x60@3x.png": 180, "AppIcon76x76~ipad.png": 76,
                "AppIcon76x76@2x~ipad.png": 152}
    for name, size in expected.items():
        png = read(name)
        assert png[:8] == b"\x89PNG\r\n\x1a\n"
        assert struct.unpack(">II", png[16:24]) == (size, size), name
        assert png[25] == 2, "Home Screen PNG must be RGB without alpha"


def check_installer():
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        prefix = root / "jb"
        helper = prefix / "usr/libexec/voidyhelper"
        helper.parent.mkdir(parents=True)
        helper.touch()
        app = prefix / "Applications/Voidy.app"
        app.mkdir(parents=True)
        bins = prefix / "usr/bin"
        bins.mkdir()
        for name in ("chown", "chmod"):
            tool = bins / name
            tool.write_text("#!/bin/sh\nexit 0\n")
            tool.chmod(0o755)
        log = root / "registration"
        uicache = bins / "uicache"
        uicache.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\" > " + shlex.quote(str(log)) + "\n")
        uicache.chmod(0o755)
        script = (ROOT / "layout/DEBIAN/postinst").read_text()
        script = script.replace("PATH=/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                                "PATH=" + shlex.quote(str(bins)) + ":/usr/bin:/bin")
        script = script.replace('for prefix in /var/jb "";', "for prefix in " + shlex.quote(str(prefix)) + ";")
        result = subprocess.run(["sh"], input=script, text=True, capture_output=True)
        assert result.returncode == 0, result.stderr
        assert log.read_text().splitlines() == ["-p", str(app)]
        uicache.write_text("#!/bin/sh\nexit 23\n")
        result = subprocess.run(["sh"], input=script, text=True, capture_output=True)
        assert result.returncode != 0 and "registration failed" in result.stderr
        helper.unlink()
        result = subprocess.run(["sh"], input=script, text=True, capture_output=True)
        assert result.returncode != 0 and "missing" in result.stderr


def check_deb(path):
    data = Path(path).read_bytes()
    assert data[:8] == b"!<arch>\n"
    archives, offset = {}, 8
    while offset < len(data):
        header = data[offset:offset + 60]
        size = int(header[48:58])
        archives[header[:16].decode().strip().rstrip("/")] = data[offset + 60:offset + 60 + size]
        offset += 60 + size + size % 2
    assert "data.tar.xz" in archives
    control_data = next(value for name, value in archives.items() if name.startswith("control.tar."))
    with tarfile.open(fileobj=io.BytesIO(control_data)) as archive:
        control_files = {m.name.lstrip("./"): archive.extractfile(m).read() for m in archive if m.isfile()}
    control = control_files["control"].decode()
    assert "Version: 1.0.4\n" in control
    assert "uikittools" in next(line for line in control.splitlines() if line.startswith("Depends:"))
    assert control_files["postinst"] == (ROOT / "layout/DEBIAN/postinst").read_bytes()
    with tarfile.open(fileobj=io.BytesIO(archives["data.tar.xz"])) as archive:
        files = {m.name.lstrip("./"): archive.extractfile(m).read() for m in archive if m.isfile()}
    app_prefix = next(name[:-len("Info.plist")] for name in files if name.endswith("Voidy.app/Info.plist"))
    check_icons(lambda name: files[app_prefix + name])
    assert app_prefix + "Voidy" in files
    assert not any(name.endswith((".swift", ".m", ".h")) for name in files)
    print("Package icons and installer verified:", path)


if __name__ == "__main__":
    check_icons(lambda name: (ROOT / "app/Resources" / name).read_bytes())
    check_installer()
    for path in sys.argv[1:]:
        check_deb(path)
    print("Icon and installer regression tests passed.")
