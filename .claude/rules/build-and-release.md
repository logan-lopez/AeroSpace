---
paths:
  - "Package.swift"
  - "Package.resolved"
  - ".swift-version"
  - "generate.sh"
  - "xcode/**"
  - "build-debug.sh"
  - "run-debug.sh"
  - "run-cli.sh"
  - "build-release.sh"
  - "build-docs.sh"
  - "build-shell-completion.sh"
  - "install-from-sources.sh"
  - "test.sh"
  - "swift-test.sh"
  - "lint.sh"
  - "format.sh"
  - "makefile"
  - "script/**"
  - ".github/workflows/**"
  - ".github/gh-actions-runner-xcode-select.sh"
  - ".swiftlint.yml"
  - ".swiftformat"
---

Before changing these files, read [Build and release](../../docs/architecture/build-and-release.md).

How AeroSpace is built, tested, linted, generated and packaged (SPM, XcodeGen, the shell entry points, CI), for sessions touching build scripts or trying to get a local debug or release build running.
