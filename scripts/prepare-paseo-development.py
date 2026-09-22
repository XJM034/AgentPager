#!/usr/bin/env python3
"""Prepare a new private development configuration. Never install or restart either app."""
import argparse
import json
import os
from pathlib import Path
import secrets
import uuid
from urllib.parse import urlparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory', type=Path)
parser.add_argument('--paseo-url', required=True)
parser.add_argument('--ingress-port', type=int, default=49463)
parser.add_argument('--hook-port', type=int, default=49461)
parser.add_argument('--phone-port', type=int, default=49462)
args = parser.parse_args()
url = urlparse(args.paseo_url)
if url.scheme != 'ws' or url.hostname not in ('127.0.0.1', 'localhost', '::1') or url.username or url.password:
    parser.error('Paseo URL must be a local ws URL without embedded credentials')
ports = (args.ingress_port, args.hook_port, args.phone_port)
if len(set(ports)) != 3 or any(p <= 1024 or p > 65535 or p in (49361, 49362) for p in ports):
    parser.error('Use three distinct non-production ports in 1025..65535')
# Refuse existing directories/configurations; preserve any user-managed configuration.
args.directory.mkdir(mode=0o700, parents=False, exist_ok=False)
config = args.directory / 'paseo-development.json'
with os.fdopen(os.open(config, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
    json.dump(dict(port=args.ingress_port, hookPort=args.hook_port, phonePort=args.phone_port,
                   token=secrets.token_hex(32), hostID=str(uuid.uuid4()), paseoURL=args.paseo_url), output, indent=2)
    output.write('\n')
print('Development configuration prepared; no app or plugin was installed or restarted.')
