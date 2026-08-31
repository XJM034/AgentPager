"""macOS integration probe using disposable signing identities and synthetic Key data.

Requires Swift, codesign, security and OpenSSL 3. Never imports into the login
keychain or changes trust settings. All private signing material is temporary.
"""

import hashlib
import json
import os
import pathlib
import secrets
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
report = {}


def run(args, timeout=20):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        # Do not include argv: import/export commands carry a disposable password.
        raise RuntimeError(f'{args[0]} timed out after {timeout}s') from None
    if r.returncode:
        raise RuntimeError(f'{args[0]} exited {r.returncode}: {r.stderr[-1200:]}')
    return r.stdout + r.stderr


before = run(['security', 'list-keychains', '-d', 'user'])
before_default = run(['security', 'default-keychain', '-d', 'user'])
with tempfile.TemporaryDirectory(prefix='agentpager-signing-probe-') as directory:
    d = pathlib.Path(directory)
    kc = d / 'isolated.keychain'
    password = secrets.token_hex(24)
    created = False
    try:
        config = d / 'certificate.cnf'
        config.write_text('''[req]
distinguished_name=dn
x509_extensions=extensions
prompt=no
[dn]
CN=AgentPager Ephemeral Signing Test
[extensions]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
''')
        run(['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-noenc', '-sha256', '-days', '1', '-config', str(config), '-keyout', str(d/'private.pem'), '-out', str(d/'certificate.pem')])
        os.chmod(d/'private.pem', 0o600)
        run(['openssl', 'pkcs12', '-export', '-legacy', '-inkey', str(d/'private.pem'), '-in', str(d/'certificate.pem'), '-out', str(d/'identity.p12'), '-passout', f'pass:{password}'])
        os.chmod(d/'identity.p12', 0o600)
        run(['security', 'create-keychain', '-p', password, str(kc)])
        created = True
        run(['security', 'import', str(d/'identity.p12'), '-k', str(kc), '-P', password, '-T', '/usr/bin/codesign'])
        report['certificate_imported_only_into_temporary_keychain'] = True
        identity = run(['openssl', 'x509', '-in', str(d/'certificate.pem'), '-noout', '-fingerprint', '-sha1']).strip().split('=')[1].replace(':','')
        main = d/'main.swift'
        source = '''import Foundation
import Security
public protocol GLMKeyStore: Sendable {
    func exists() throws -> Bool
    func load() throws -> String?
    func authorizeAccess() throws
    func save(_ key: String) throws
    func delete() throws
}
public enum GLMKeyAccessError: Error, Equatable, Sendable {
    case authorizationRequired, authorizationNotPersistent
}
let flavor = "FLAVOR"
var keychain: SecKeychain?
guard SecKeychainOpen(CommandLine.arguments[1], &keychain) == errSecSuccess else { exit(2) }
let store = GLMKeychainStore(service: "agentpager-signing-probe", account: "synthetic", keychain: keychain)
do {
    if CommandLine.arguments[2] == "write" { try store.save("synthetic-signing-probe-value") }
    let matched = try store.load() == "synthetic-signing-probe-value"
    print("\\(flavor): read matched=\\(matched)")
    if CommandLine.arguments[2] == "expect-denied" { exit(6) }
    exit(matched ? 0 : 3)
} catch let error as GLMKeyAccessError {
    print("\\(flavor): \\(error)")
    exit(CommandLine.arguments[2] == "expect-denied" && error == .authorizationRequired ? 0 : 4)
} catch {
    print("\\(flavor): unexpected keychain error")
    exit(5)
}
'''
        for flavor in ['A','B']:
            main.write_text(source.replace('FLAVOR',flavor))
            executable = d/flavor
            run(['swiftc', '-o', str(executable), str(root/'macos/Sources/AgentGridCore/GLMKeychainStore.swift'), str(root/'macos/Sources/AgentGridCore/KeychainAccess.swift'), str(main)], timeout=30)
            run(['codesign', '--force', '--sign', identity, '--keychain', str(kc), '--identifier', 'com.agentpager.signing-probe', '--timestamp=none', str(executable)])
            report[f'{flavor}_requirement'] = run(['codesign', '-d', '-r-', str(executable)]).split('designated => ')[-1].splitlines()[0].strip()
            report[f'{flavor}_verification'] = run(['codesign', '--verify', '--strict', str(executable)]).strip() or 'passed'
            report[f'{flavor}_sha256'] = hashlib.sha256(executable.read_bytes()).hexdigest()
        report['same_designated_requirement'] = report['A_requirement'] == report['B_requirement']
        report['different_binaries'] = report['A_sha256'] != report['B_sha256']
        report['initial_write_and_read'] = run([str(d/'A'), str(kc), 'write']).strip()
        report['same_version_restart'] = run([str(d/'A'), str(kc), 'read']).strip()
        report['updated_binary_read'] = run([str(d/'B'), str(kc), 'read']).strip()
        run(['codesign', '--force', '--sign', '-', '--identifier', 'com.agentpager.signing-probe', str(d/'B')])
        report['changed_identity_denied_silently'] = run([str(d/'B'), str(kc), 'expect-denied']).strip()
    except Exception as error:
        report['error'] = str(error)
    finally:
        if created:
            report['temporary_keychain_deleted'] = run(['security', 'delete-keychain', str(kc)]).strip() or True
report['user_search_list_unchanged'] = before == run(['security', 'list-keychains', '-d', 'user'])
report['default_keychain_unchanged'] = before_default == run(['security', 'default-keychain', '-d', 'user'])
(root/'dist').mkdir(exist_ok=True)
(root/'dist/glm-signing-probe-result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
required = ['same_designated_requirement', 'different_binaries', 'temporary_keychain_deleted',
            'user_search_list_unchanged', 'default_keychain_unchanged']
raise SystemExit(1 if 'error' in report or not all(report.get(key) for key in required) else 0)
