# AGENTS

## Overview
This repository contains a Flutter application. A setup script is automatically executed in the environment to install Flutter packages and run any required build steps. Run `flutter pub get` **only** when adding, removing, or updating packages.

## Development Guidelines
- Format code with `dart format -o write .` before committing.
- Generated files (`*.g.dart`) are produced via `flutter pub run build_runner build --delete-conflicting-outputs`. Run this after editing source files that depend on code generation.
- Do not commit `lib/apiSecretKeys.dart` – this file is ignored and can contain local secrets.
- Any new function added to Flutter code must include a documentation comment
  using the standard Flutter format, describing the function's action and
  purpose when applicable.

## Testing
Run tests with:
```bash
flutter test
```
