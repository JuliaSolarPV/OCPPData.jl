# [Architecture](@id architecture)

## Overview

OCPP.jl generates all message types at **module load time** from the official OCPP JSON schema files. No types are hand-written — they are created programmatically via `Core.eval` when `using OCPP` is first called.

```
JSON schema files (src/v16/schemas/, src/v201/schemas/)
        │
        ▼
  schema_reader.jl  ──── reads schemas, generates:
        │                   • @enum types (with JSON serialization)
        │                   • @kwdef structs (with camelCase mapping)
        │                   • action registries
        ▼
  V16 / V201 submodules  ──── contain all generated types
```

## Schema-Driven Type Generation

The core logic lives in `src/schema_reader.jl`. There are two code paths, one per OCPP version:

### V16: `generate_types!`

V16 schemas are flat — each file defines one request or response with inline property definitions. Enum values appear as `"enum": [...]` arrays directly inside properties.

Because V16 schemas don't name their enum types or nested objects, OCPP.jl uses **hand-curated registries** (in `src/v16/registries.jl`):

- **`V16_ENUM_REGISTRY`**: Maps sorted enum value lists → `(EnumTypeName, member_prefix)`. This is how the package knows that `["Accepted", "Pending", "Rejected"]` should become `RegistrationStatus`.
- **`V16_NESTED_TYPE_NAMES`**: Maps JSON property names → Julia type names for shared nested objects (e.g., `"idTagInfo" => :IdTagInfo`).

The generation pipeline:

1. **Read schemas** — parse all `.json` files from `src/v16/schemas/`
2. **Collect enums** — walk all properties, match enum value sets against the registry, generate `@enum` types with forward/reverse string lookup dicts
3. **Collect nested types** — find object-typed properties named in `V16_NESTED_TYPE_NAMES`, topologically sort by dependency, generate structs
4. **Generate action structs** — one struct per schema file (e.g., `BootNotificationRequest`)
5. **Build action registry** — `V16_ACTIONS` dict mapping `"BootNotification" => (request=..., response=...)`

### V201: `generate_types_from_definitions!`

V201 schemas use JSON Schema's `definitions` + `$ref` pattern. Each schema file contains a `definitions` section with named types like `"ChargingStationType"` and `"BootReasonEnumType"`, referenced via `"$ref": "#/definitions/..."`.

Because types are explicitly named in the schemas, V201 needs **no hand-curated registry**. Names are derived automatically:
- `"BootReasonEnumType"` → `BootReason` (strip `EnumType` suffix)
- `"ChargingStationType"` → `ChargingStation` (strip `Type` suffix)
- Enum member prefixes are auto-derived from the definition name, applied when values collide across enums or shadow Base names

The generation pipeline:

1. **Read schemas** — parse all `.json` files from `src/v201/schemas/`
2. **Merge definitions** — collect all `definitions` sections across schema files into one dict
3. **Classify definitions** — separate into enum definitions (have `"enum"` key) and object definitions (have `"properties"`)
4. **Generate enums** — derive names and prefixes, create `@enum` types
5. **Generate object types** — topologically sort by `$ref` dependencies, generate structs
6. **Generate action structs** — one struct per schema file
7. **Build action registry** — `V201_ACTIONS` dict

## Inspecting Generated Types

You can inspect the generated types at runtime:

```@example arch
using OCPP
using OCPP.V16
import JSON
nothing # hide
```

Struct fields (shows snake\_case names and types):

```@example arch
fieldnames(BootNotificationRequest)
```

```@example arch
fieldtypes(BootNotificationRequest)
```

Enum members:

```@example arch
instances(RegistrationStatus) |> collect
```

All V16 action names:

```@example arch
sort(collect(keys(V16.V16_ACTIONS)))
```

All V201 action names:

```@example arch
sort(collect(keys(OCPP.V201.V201_ACTIONS)))
```

## How Types Are Generated

All types are created via `Core.eval` into the target module (V16 or V201):

### Enums

Each OCPP enum becomes a Julia `@enum` with:
- Forward dict: `EnumMember => "OCPPStringValue"`
- Reverse dict: `"OCPPStringValue" => EnumMember`
- `Base.string(x)` override returning the OCPP wire value
- `StructUtils.lift(T, s)` override for deserialization from JSON strings

```@example arch
# string() returns the OCPP wire value, not the Julia member name
string(RegistrationAccepted)
```

### Structs

Each message type becomes a `Base.@kwdef` struct with:
- Required fields as plain typed fields (e.g., `charge_point_vendor::String`)
- Optional fields as `Union{T, Nothing}` with default `nothing`
- `StructUtils.fieldtags` mapping `snake_case` Julia names ↔ `camelCase` JSON names
- Empty structs (like `HeartbeatRequest`) get `StructUtils.structlike(::Type{T}) = true` so they serialize as `{}` instead of a string

```@example arch
# Empty struct serializes as {}
JSON.json(HeartbeatRequest())
```

```@example arch
# camelCase on the wire, snake_case in Julia
JSON.json(BootNotificationRequest(
    charge_point_vendor = "V",
    charge_point_model = "M",
))
```

### Action Registry

A `Dict{String, NamedTuple{(:request, :response), ...}}` constant with helper functions `request_type(action)` and `response_type(action)`.

```@example arch
V16.V16_ACTIONS["Heartbeat"]
```

## Module Structure

```
module OCPP                          # top-level
├── messages.jl                      # Call, CallResult, CallError types
├── codec.jl                         # encode/decode OCPP-J wire format
├── schema_reader.jl                 # type generation engine (version-agnostic)
├── validation.jl                    # JSONSchema.jl validation layer
│
├── module V16                       # submodule — all V16 types
│   ├── v16/registries.jl            # hand-curated enum + nested type registries
│   └── v16/schemas/*.json           # official OCPP 1.6 JSON schemas
│
└── module V201                      # submodule — all V201 types
    └── v201/schemas/*.json          # official OCPP 2.0.1 JSON schemas
```

The `schema_reader.jl` functions are called from the top-level `OCPP` module but `Core.eval` their output into the V16/V201 submodules. This is why V16 and V201 use `using ..OCPP: generate_types!` — the generation logic is shared, but the generated types live in the version-specific namespace.
