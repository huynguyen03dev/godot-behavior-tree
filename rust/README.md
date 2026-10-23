# godot_bt_native — Rust runtime port

Native (Rust/GDExtension) port of the `godot_bt` behavior tree runtime.
The GDScript addon under `addons/godot_bt/` stays the source of truth until this
port reaches full parity; afterwards the GDScript runtime is removed and the
editor plugin is updated to talk to the native classes.

## Layout

- `src/` — Rust crate (registered classes: `BTNativeVersion`, later
  `BTTreeNative`, `BTBlackboardNative`, `BTRunnerNative`)
- `build.sh` — builds debug+release and installs the binaries into
  `addons/godot_bt_native/bin/` (referenced by `godot_bt_native.gdextension`)
- Engine: Godot 4.7.x, [gdext](https://godot-rust.github.io/) 0.5
  (API target 4.6 → runs on any 4.6+ runtime, incl. 4.7.2)

## Build

```bash
bash rust/build.sh                 # debug + release
bash rust/build.sh --release-only  # perf runs
```

Binaries land in `addons/godot_bt_native/bin/` and are gitignored; every
developer/CI builds them locally with one command (requires `rustup`).

## Parity & testing

- `cargo test` for pure-Rust logic (model, serialization, scoping).
- Godot headless suites under `tests/` exercise the native runner against the
  same JSON trees used by the GDScript runtime (see port waves).
