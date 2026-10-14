#!/usr/bin/env python3
"""Create a persistent development identity in an isolated, ignored keychain.

No certificate is added to a trust store. Restore the user's keychain search list
after creation; codesign selects this keychain explicitly.
"""
import hashlib
import os
from pathlib import Path
import secrets
import shlex
import subprocess

folder = Path(__file__).resolve().parent.parent / "build/local-signing"
folder.mkdir(parents=True, exist_ok=True, mode=0o700)
os.chmod(folder, 0o700)
keychain = folder / "ErgoDevelopment.keychain-db"
password_file = folder / "keychain-password"
certificate = folder / "certificate.pem"


def run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, **kwargs)
    if result.returncode:
        # Do not echo subprocess arguments, which can contain the private password.
        raise SystemExit(f"Local signing setup failed in {Path(args[0]).name}: "
                         + result.stderr.decode(errors="replace"))
    return result.stdout


if keychain.exists() != password_file.exists():
    raise SystemExit("Incomplete local signing keychain; preserve it and investigate before retrying")
existing = keychain.exists()
has_identity = existing and b"1)" in run(["security", "find-identity", "-p", "codesigning", str(keychain)])
if not has_identity:
    if existing:
        password = password_file.read_text()
    else:
        password = secrets.token_urlsafe(32)
        password_file.write_text(password)
        os.chmod(password_file, 0o600)
    configuration = folder / "certificate.cnf"
    configuration.write_text("""[req]
distinguished_name = name
x509_extensions = extensions
prompt = no
[name]
CN = Ergo Control Local Development
[extensions]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
""")
    private_key, package = folder / "private-key.pem", folder / "identity.p12"
    try:
        run(["openssl", "req", "-x509", "-newkey", "rsa:3072", "-nodes", "-days", "3650",
             "-config", str(configuration), "-keyout", str(private_key), "-out", str(certificate)])
        os.chmod(private_key, 0o600)
        run(["openssl", "pkcs12", "-export", "-inkey", str(private_key), "-in", str(certificate),
             "-out", str(package), "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES",
             "-macalg", "sha1", "-passout", "stdin"], input=(password + "\n").encode())
        os.chmod(package, 0o600)
        if not existing:
            run(["security", "create-keychain", "-p", password, str(keychain)])
        run(["security", "unlock-keychain", "-p", password, str(keychain)])
        run(["security", "import", str(package), "-k", str(keychain), "-P", password,
             "-T", "/usr/bin/codesign"])
        run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", password, str(keychain)])
    finally:
        current = shlex.split(run(["security", "list-keychains", "-d", "user"]).decode())
        # Preserve other search-list edits if another process made one during setup.
        restored = [item for item in current if Path(item).resolve() != keychain.resolve()]
        if current != restored:
            run(["security", "list-keychains", "-d", "user", "-s", *restored])
        private_key.unlink(missing_ok=True); package.unlink(missing_ok=True)
else:
    run(["security", "unlock-keychain", "-p", password_file.read_text(), str(keychain)])
der = run(["openssl", "x509", "-in", str(certificate), "-outform", "DER"])
# Certificate fingerprints are public; only this value is returned to the build script.
print(hashlib.sha1(der).hexdigest())
