#!/usr/bin/env python3
"""Build opt-in local helper installers. Does not install, bootstrap, or register anything."""
from pathlib import Path
import os
import plistlib
import shlex
import shutil
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
work = app.parent / "helper-packages"
work.mkdir(parents=True, exist_ok=True)
helper = app / "Contents/Library/HelperTools/ErgoInputHelper"
service = "dev.local.ergocontrol.inputhelper"
tool_path = "/Library/PrivilegedHelperTools/" + service
plist_path = "/Library/LaunchDaemons/" + service + ".plist"
result = subprocess.run(["codesign", "--display", "--requirements", "-", str(helper)],
                        capture_output=True, text=True, check=True)
requirement = next(line.removeprefix("designated => ") for line in (result.stdout + result.stderr).splitlines()
                   if line.startswith("designated => "))
if "certificate" not in requirement and "anchor" not in requirement:
    raise SystemExit("The helper installer requires certificate signing")

# Every elevated operation uses fixed paths. Refuse to replace/remove a helper
# signed by a different developer or an unprotected/symlinked installation.
guard = f"""#!/bin/sh
set -eu
tool={shlex.quote(tool_path)}
plist={shlex.quote(plist_path)}
service={shlex.quote(service)}
if [ "$(/usr/bin/id -u)" != 0 ]; then
  echo 'This package must be run through the macOS administrator installer.' >&2
  exit 1
fi
for location in /Library/PrivilegedHelperTools /Library/LaunchDaemons "$tool" "$plist"; do
  if [ -L "$location" ]; then
    echo 'Refusing a symlinked helper installation.' >&2
    exit 1
  fi
  if [ -e "$location" ]; then
    if [ "$(/usr/bin/stat -f %u "$location")" != 0 ]; then
      echo 'Refusing a helper location not owned by root.' >&2
      exit 1
    fi
    permissions=$(/usr/bin/stat -f %Lp "$location")
    case "$permissions" in
      *[2367][0-7]|*[0-7][2367]) echo 'Refusing a writable helper location.' >&2; exit 1 ;;
    esac
  fi
done
if [ -e "$tool" ]; then
  if [ ! -f "$tool" ]; then echo 'The helper path is not a file.' >&2; exit 1; fi
  /usr/bin/codesign --verify --strict --test-requirement {shlex.quote('='+requirement)} "$tool"
fi
"""
stop = """if /bin/launchctl print "system/$service" >/dev/null 2>&1; then
  /bin/launchctl bootout "system/$service"
fi
"""


def script(folder, name, text):
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / name
    target.write_text(text)
    target.chmod(0o755)
    subprocess.run(["/bin/sh", "-n", str(target)], check=True)


payload = work / "payload"
tools = payload / "Library/PrivilegedHelperTools"
daemons = payload / "Library/LaunchDaemons"
tools.mkdir(parents=True, exist_ok=True)
daemons.mkdir(parents=True, exist_ok=True)
shutil.copyfile(helper, tools / service)
(tools / service).chmod(0o755)
(daemons / (service + ".plist")).write_bytes(plistlib.dumps({
    "Label": service, "Program": tool_path,
    "AssociatedBundleIdentifiers": ["dev.local.ergocontrol.app"],
    "MachServices": {service: True}, "ProcessType": "Interactive",
    "ThrottleInterval": 1,
}))
(daemons / (service + ".plist")).chmod(0o644)
install_scripts, remove_scripts = work / "install-scripts", work / "remove-scripts"
script(install_scripts, "preinstall", guard + stop)
script(install_scripts, "postinstall", guard + """/bin/launchctl enable "system/$service"
/bin/launchctl bootstrap system "$plist"
echo 'Ergo Control input helper installed. No input is captured until mappings are enabled.'
""")
script(remove_scripts, "postinstall", guard + stop + """/bin/rm -f "$tool" "$plist"
/usr/sbin/pkgutil --forget dev.local.ergocontrol.inputhelper.install >/dev/null 2>&1 || true
echo 'Ergo Control input helper removed. App settings were preserved.'
""")
output = app / "Contents/Resources"
output.mkdir(parents=True, exist_ok=True)
package_environment = dict(os.environ, COPYFILE_DISABLE="1")
subprocess.run(["pkgbuild", "--root", str(payload), "--ownership", "recommended",
                "--identifier", service + ".install", "--version", "0.2.2",
                "--install-location", "/", "--scripts", str(install_scripts),
                str(output / "ErgoInputHelper-Install.pkg")], check=True, env=package_environment)
subprocess.run(["pkgbuild", "--nopayload", "--identifier", service + ".uninstall",
                "--version", "0.2.2", "--scripts", str(remove_scripts),
                str(output / "ErgoInputHelper-Uninstall.pkg")], check=True, env=package_environment)
