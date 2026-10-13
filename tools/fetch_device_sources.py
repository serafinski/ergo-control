#!/usr/bin/env python3
"""Download public, device-specific Razer sources for static analysis only."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import urljoin

BASE = "https://apps-mac.razer.com/synapse/products/708/mw/"
OUT = Path(__file__).resolve().parents[1] / "analysis/vendor/708/mw"


def fetch(name):
    if not re.fullmatch(r"[\w./@-]+", name) or ".." in name.split("/"):
        raise ValueError(name)
    target = OUT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        subprocess.run(["curl", "--fail", "--silent", "--show-error", "--location",
                        "--max-time", "25", urljoin(BASE, name), "-o", str(target)], check=True)
    return name


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    fetch("index.html")
    html = (OUT / "index.html").read_text()
    entry = re.search(r'src="\./([^"?]+\.js)"', html).group(1)
    fetch(entry)
    main_js = (OUT / entry).read_text()
    # Webpack's runtime names lazy-loaded chunks as <id>.<hash>.js.
    aliases = dict(re.findall(r'(\d+):"(rz\w+)"', main_js))
    names = {f"{aliases.get(n, n)}.{h}.js" for n, h in re.findall(r'(\d+):"([a-f0-9]{20})"', main_js)}
    names |= {"sw.js", "installer-manifest.json", "manifests/manifest-1.0.0.json"}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        jobs = {pool.submit(fetch, n): n for n in sorted(names)}
        for job, name in jobs.items():
            try:
                print("Saved", job.result())
            except Exception as error:
                print("Unavailable", name, type(error).__name__)
    manifest = {}
    for p in sorted(OUT.rglob("*")):
        if p.is_file() and p.name != "SOURCES.json":
            data = p.read_bytes()
            manifest[str(p.relative_to(OUT))] = {
                "url": urljoin(BASE, str(p.relative_to(OUT))),
                "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
    (OUT / "SOURCES.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Preserved {len(manifest)} source files; no downloaded code executed.")


if __name__ == "__main__":
    main()
