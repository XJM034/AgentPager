#!/usr/bin/env python3
"""Package the locked local plugin and its runtime dependencies; never install it."""
import json
from pathlib import Path
import shutil
import sys

source = Path(__file__).resolve().parents[1] / 'integrations/paseo-omp'
destination = Path(sys.argv[1]) / 'paseo-omp'
staging = destination.with_name('paseo-omp-staging')
if staging.exists():
    shutil.rmtree(staging)
staging.mkdir(parents=True)
for name in ('index.server.ts', 'paseo-plugin.json', 'package.json', 'package-lock.json'):
    shutil.copy2(source / name, staging / name)
shutil.copytree(source / 'server', staging / 'server')
# The plugin contract import is type-only. Runtime imports use the public SDK root.
pending = ['@getpaseo/client']
copied = set()
while pending:
    name = pending.pop()
    if name in copied:
        continue
    package = source / 'node_modules' / name
    manifest = json.loads((package / 'package.json').read_text())
    shutil.copytree(package, staging / 'node_modules' / name)
    copied.add(name)
    pending.extend(manifest.get('dependencies', {}))
# Package files retain each dependency's license and notice files.
(staging / 'BUNDLED-DEPENDENCIES.txt').write_text('\n'.join(sorted(copied)) + '\n')
if destination.exists():
    shutil.rmtree(destination)
staging.rename(destination)
print('Packaged Paseo plugin and', len(copied), 'runtime packages; not installed.')
