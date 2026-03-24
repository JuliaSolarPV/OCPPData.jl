# [Architecture](@id architecture)

## Module Structure

```text
module OCPPData                          # top-level
├── messages.jl                      # Call, CallResult, CallError types
├── codec.jl                         # encode/decode OCPP-J wire format
├── schema_reader.jl                 # type generation engine (version-agnostic)
├── validation.jl                    # JSONSchema.jl validation layer
│
├── module V16                       # submodule — all V16 types
│   ├── v16/registries.jl            # hand-curated enum + nested type registries
│   └── v16/schemas/*.json           # official OCPP 1.6 JSON schemas (56 files)
│
└── module V201                      # submodule — all V201 types
    └── v201/schemas/*.json          # official OCPP 2.0.1 JSON schemas (128 files)
```

The top-level `OCPPData` module provides the wire-level types (`Call`, `CallResult`, `CallError`), the codec (`encode`/`decode`), and schema validation (`validate`). The version submodules V16 and V201 contain all OCPP message structs and enums — these are generated at load time from the JSON schema files. See [Schema-Driven Type Generation](@ref type-generation) for a detailed walkthrough of how this works.

Which version submodules are loaded is controlled by the `protocol_version` preference (`"all"`, `"v16"`, or `"v201"`). When a version is disabled, its module file is not `include`d, its schemas are not loaded, and its precompile workload is skipped. See the [Usage Guide](@ref) for configuration details.

## Key Design Decisions

### Why generate types from schemas?

The OCPP specification defines 28 actions (V16) and 64 actions (V201), each with request and response payloads. Hand-writing 200+ structs would be error-prone and hard to keep in sync with the spec. Instead, the official JSON schema files are the single source of truth.

### Why two code paths?

V16 and V201 schemas have fundamentally different structures:

- **V16**: Flat schemas — each file has inline properties, no named types. Requires a hand-curated registry to name enums and shared types.
- **V201**: Self-describing schemas — uses `definitions` + `$ref` with explicit type names. No registry needed.

This is handled by two macros in `schema_reader.jl`: `@generate_ocpp_types` (V16) and `@generate_ocpp_types_from_definitions` (V201).

### Why macros?

Types are determined from data (JSON files), not from source code. The two macros read the schema files at macro-expansion time, build Julia AST (`Expr` objects) for all enums, structs, and registries, and return that AST via `esc(Expr(:block, ...))` — standard macro expansion. The cost is paid once at precompilation and cached.

### Why submodules?

V16 and V201 define types with the same names (e.g., both have `BootNotificationRequest`) but with different fields. Putting them in separate submodules avoids name collisions and lets users import only the version they need:

```@example arch
using OCPPData

# V16 BootNotificationRequest has charge_point_vendor, charge_point_model, ...
fieldnames(OCPPData.V16.BootNotificationRequest)
```

```@example arch
# V201 BootNotificationRequest has reason, charging_station, ...
fieldnames(OCPPData.V201.BootNotificationRequest)
```

## Data Flow

```text
                    ┌─────────────────────────────────────────┐
                    │            Precompilation                │
                    │                                         │
                    │  JSON schemas ──→ schema_reader.jl      │
                    │                     │                   │
                    │              macro expansion            │
                    │                     │                   │
                    │              V16/V201 modules           │
                    │          (structs, enums, registry)     │
                    └─────────────────────────────────────────┘

                    ┌─────────────────────────────────────────┐
                    │              Runtime                     │
                    │                                         │
  WebSocket ──→ decode() ──→ validate() ──→ JSON.parse(,T)   │
   frame         codec.jl    validation.jl    StructUtils     │
                    │                            │            │
                    │                     Typed struct         │
                    │                            │            │
                    │                    Application logic     │
                    │                            │            │
                    │                     JSON.json(resp)     │
  WebSocket ←── encode() ←──────────────────────┘            │
   frame         codec.jl                                     │
                    └─────────────────────────────────────────┘
```
