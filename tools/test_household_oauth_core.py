#!/usr/bin/env python3
"""Run the exact Swift PKCE/callback logic natively when Simulator is unavailable.

The source enum is copied verbatim; only the app's UI-facing error type is
stubbed. Reuse the same Swift Testing suite. This does NOT test browser/iPhone
handoff, ASWebAuthenticationSession, Keychain integration or actual SSO.
"""
import os
from pathlib import Path
import platform
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'ios/BoulderBikeRouter/BoulderBikeRouter/Services/HouseholdOAuth.swift').read_text()
start = source.index('enum HouseholdOAuthRequest {')
end = source.index('\n@MainActor\nfinal class HouseholdOAuth')
core = source[start:end]
suite = (ROOT / 'ios/BoulderBikeRouter/BoulderBikeRouterTests/HouseholdOAuthTests.swift').read_text()
suite = suite.replace('@testable import BoulderBikeRouter', '@testable import HouseholdOAuthCore')
if platform.system() != 'Darwin' or platform.machine() != 'arm64':
    raise SystemExit('Run with the native Apple silicon Mac toolchain')
cache = Path.home() / 'Library/Caches'
with tempfile.TemporaryDirectory(prefix='lockdev-oauth-core-', dir=cache) as temporary:
    package = Path(temporary)
    (package / 'Sources/HouseholdOAuthCore').mkdir(parents=True)
    (package / 'Tests/HouseholdOAuthCoreTests').mkdir(parents=True)
    (package / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "HouseholdOAuthCore", platforms: [.macOS(.v13)], targets: [
    .target(name: "HouseholdOAuthCore"),
    .testTarget(name: "HouseholdOAuthCoreTests", dependencies: ["HouseholdOAuthCore"])
])
''')
    (package / 'Sources/HouseholdOAuthCore/Core.swift').write_text(
        'import Foundation\nimport CryptoKit\nimport Security\n'
        'enum APIError: Error { case invalidURL; case serverError(String) }\n' + core)
    (package / 'Tests/HouseholdOAuthCoreTests/HouseholdOAuthTests.swift').write_text(suite)
    log_path = cache / 'lockdev-household-oauth-core-tests.log'
    with log_path.open('w') as log:
        process = subprocess.Popen(['xcrun', 'swift', 'test', '--package-path', str(package)],
            stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            process.wait(timeout=180)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=15)
            raise SystemExit(f'Native OAuth core tests exceeded three minutes; see {log_path}')
    print(log_path.read_text()[-5000:])
    raise SystemExit(process.returncode)
