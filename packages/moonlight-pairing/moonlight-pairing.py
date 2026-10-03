"""Pre-generate a Moonlight <-> Sunshine pairing, so neither side ever needs
the PIN dance.

Pairing is nothing but two self-signed certs that each side pins:

- Sunshine serves its own cert/key (the `cert`/`pkey` settings) and lets in
  a client whose cert is byte-for-byte one of `root.named_devices[].cert` in
  sunshine_state.json (nvhttp.cpp: verify_client_certificate).
- Moonlight presents its own cert/key (Moonlight.conf `certificate`/`key`)
  and trusts a host whose cert equals that host's `srvcert`, under the
  host's `uuid`, which has to be Sunshine's `root.uniqueid`.

The certs mirror what each program makes for itself (Sunshine's
crypto::gen_creds, moonlight-qt's IdentityManager::createCredentials):
RSA 2048, SHA-256, twenty years, subject = issuer = one CN. The serial is
random rather than their 0, which `cryptography` refuses; neither side
looks at it.

Writes into OUTDIR, which has to be new or empty:

  public.json             certs and ids, none of it secret: copy it into
                          nixconf as modules/gaming/moonlight-pairing.json
  sunshine-key.pem        the gaming desktop's private key
  moonlight-<client>.pem  each client's private key

Re-run it to rotate: a new public.json plus new keys, which replace the old
ones in 1Password.
"""

import argparse
import datetime
import json
import os
import secrets
import sys
import uuid
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

TWENTY_YEARS = datetime.timedelta(days=365 * 20)


def identity(common_name):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(now + TWENTY_YEARS)
        .sign(key, hashes.SHA256())
    )
    key_pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    return key_pem, cert.public_bytes(serialization.Encoding.PEM).decode()


def write_private(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("outdir", type=Path)
    parser.add_argument(
        "clients",
        nargs="*",
        default=["ganymede"],
        help="Moonlight clients to pair, by hostname (default: ganymede)",
    )
    args = parser.parse_args()

    os.umask(0o077)
    args.outdir.mkdir(mode=0o700, parents=True, exist_ok=True)
    if any(args.outdir.iterdir()):
        sys.exit(f"{args.outdir} isn't empty; pick a new dir so no key is overwritten")

    server_key, server_cert = identity("Sunshine Gamestream Host")
    write_private(args.outdir / "sunshine-key.pem", server_key)

    clients = {}
    for name in args.clients:
        client_key, client_cert = identity("NVIDIA GameStream Client")
        write_private(args.outdir / f"moonlight-{name}.pem", client_key)
        clients[name] = {
            # Sunshine's own id for the paired device (named_devices[].uuid).
            "uuid": str(uuid.uuid4()).upper(),
            # What Moonlight calls itself in requests: 16 hex digits, as
            # IdentityManager::getUniqueId makes it.
            "uniqueid": secrets.token_hex(8),
            "cert": client_cert,
        }

    public = {
        "server": {"uniqueid": str(uuid.uuid4()).upper(), "cert": server_cert},
        "clients": clients,
    }
    (args.outdir / "public.json").write_text(json.dumps(public, indent=2) + "\n")
    os.chmod(args.outdir / "public.json", 0o644)

    keys = ", ".join(f"moonlight-{n}.pem" for n in args.clients)
    print(f"wrote {args.outdir}: public.json, sunshine-key.pem, {keys}")


if __name__ == "__main__":
    main()
