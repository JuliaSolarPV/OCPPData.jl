"""
Read OCPP JSON schema files and generate Julia types at module load time.

Version-agnostic logic for:
- Reading JSON schema files
- Extracting enum value sets and generating @enum types
- Extracting struct field definitions and generating @kwdef structs
- Building action registries

Each OCPP version provides its own `enum_registry` and `nested_type_names`
mappings, then calls `generate_types!` with those registries.
"""

# ---------------------------------------------------------------------------
# Schema reading
# ---------------------------------------------------------------------------

"""
    read_schemas(schema_dir::String) -> Dict{String, Any}

Read all JSON schema files from a directory. Returns a Dict mapping
schema title (e.g. "BootNotificationRequest") to parsed schema.
"""
function read_schemas(schema_dir::String)
    schemas = Dict{String,Any}()
    for fname in readdir(schema_dir)
        endswith(fname, ".json") || continue
        path = joinpath(schema_dir, fname)
        schema = JSON.parse(read(path, String), Dict{String,Any})
        title = get(schema, "title", replace(fname, ".json" => ""))
        schemas[title] = schema
    end
    return schemas
end

# ---------------------------------------------------------------------------
# Enum helpers
# ---------------------------------------------------------------------------

"""Convert an OCPP enum string value to a valid Julia identifier."""
function _ocpp_string_to_identifier(s::String)
    return replace(s, "." => "", "-" => "")
end

"""Create a Julia enum member name from a prefix and OCPP string value."""
function _make_member_name(prefix::String, value::String)
    clean = _ocpp_string_to_identifier(value)
    if isempty(prefix)
        return Symbol(clean)
    end
    # Don't double-prefix if value already starts with prefix-like text
    if startswith(clean, prefix)
        return Symbol(clean)
    end
    return Symbol(prefix, clean)
end

"""
    collect_enums(schemas, enum_registry) -> Dict{Symbol, Vector{Pair{Symbol,String}}}

Scan all schemas, extract unique enum value sets, look up names in
the registry, and return a Dict mapping enum type name →
[(member_name => "OCPPString"), ...].
"""
function collect_enums(schemas, enum_registry::Dict{Vector{String},Tuple{Symbol,String}})
    seen = Set{Vector{String}}()
    result = Dict{Symbol,Vector{Pair{Symbol,String}}}()

    function _walk_enum_props(props)
        for (_, prop) in props
            prop isa AbstractDict || continue
            if haskey(prop, "enum")
                values = sort(String[string(v) for v in prop["enum"]])
                if values ∉ seen
                    push!(seen, values)
                    if haskey(enum_registry, values)
                        enum_name, prefix = enum_registry[values]
                        members = Pair{Symbol,String}[]
                        for v in prop["enum"]
                            sv = string(v)
                            member = _make_member_name(prefix, sv)
                            push!(members, member => sv)
                        end
                        result[enum_name] = members
                    end
                end
            end
            if get(prop, "type", nothing) == "object" && haskey(prop, "properties")
                _walk_enum_props(prop["properties"])
            end
            if get(prop, "type", nothing) == "array" && haskey(prop, "items")
                items = prop["items"]
                if items isa AbstractDict && get(items, "type", nothing) == "object"
                    if haskey(items, "properties")
                        _walk_enum_props(items["properties"])
                    end
                end
            end
        end
    end

    for (_, schema) in schemas
        if haskey(schema, "properties")
            _walk_enum_props(schema["properties"])
        end
    end
    return result
end

# ---------------------------------------------------------------------------
# Struct field helpers
# ---------------------------------------------------------------------------

"""Map a JSON schema property to a Julia type expression."""
function _json_type_to_julia(
    prop::AbstractDict{String,Any},
    field_name::String,
    enum_lookup::Dict{Vector{String},Symbol},
    nested_type_names::Dict{String,Symbol},
)
    if haskey(prop, "enum")
        values = sort(String[string(v) for v in prop["enum"]])
        if haskey(enum_lookup, values)
            return enum_lookup[values]
        end
        return :String
    end

    jtype = get(prop, "type", "string")
    if jtype == "string"
        return :String
    elseif jtype == "integer"
        return :Int
    elseif jtype == "number"
        return :Float64
    elseif jtype == "boolean"
        return :Bool
    elseif jtype == "object"
        if haskey(nested_type_names, field_name)
            return nested_type_names[field_name]
        end
        return :(Dict{String,Any})
    elseif jtype == "array"
        items = get(prop, "items", Dict{String,Any}())
        if items isa AbstractDict
            item_type = get(items, "type", "string")
            if item_type == "object"
                if haskey(nested_type_names, field_name)
                    inner = nested_type_names[field_name]
                    return :(Vector{$inner})
                end
                return :(Vector{Dict{String,Any}})
            elseif item_type == "string"
                return :(Vector{String})
            elseif item_type == "integer"
                return :(Vector{Int})
            end
        end
        return :(Vector{Any})
    end
    return :Any
end

"""Convert camelCase to snake_case."""
function _camel_to_snake(s::String)::String
    result = replace(s, r"([a-z0-9])([A-Z])" => s"\1_\2")
    return lowercase(result)
end

"""Extract field definitions from a JSON schema."""
function struct_fields_from_schema(
    schema::AbstractDict{String,Any},
    enum_lookup::Dict{Vector{String},Symbol},
    nested_type_names::Dict{String,Symbol},
)
    props = get(schema, "properties", Dict{String,Any}())
    required_set = Set{String}(get(schema, "required", String[]))

    fields =
        NamedTuple{(:json_name, :jl_name, :type, :required),Tuple{String,Symbol,Any,Bool}}[]

    for (json_name, prop) in props
        prop isa AbstractDict || continue
        jl_name = Symbol(_camel_to_snake(json_name))
        jl_type = _json_type_to_julia(prop, json_name, enum_lookup, nested_type_names)
        is_required = json_name in required_set
        push!(
            fields,
            (
                json_name = json_name,
                jl_name = jl_name,
                type = jl_type,
                required = is_required,
            ),
        )
    end

    # Sort: required fields first, then optional, alphabetical within each
    sort!(fields; by = f -> (!f.required, f.json_name))
    return fields
end

"""
Collect all nested object types that need to be generated as shared
sub-types. Returns them in dependency order (leaves first).
"""
function collect_nested_types(
    schemas,
    enum_lookup::Dict{Vector{String},Symbol},
    nested_type_names::Dict{String,Symbol},
)
    nested = Dict{Symbol,Any}()

    function _walk_nested_props(props)
        for (name, prop) in props
            prop isa AbstractDict || continue
            ptype = get(prop, "type", nothing)

            if ptype == "object" && haskey(prop, "properties")
                if haskey(nested_type_names, name)
                    tname = nested_type_names[name]
                    if !haskey(nested, tname)
                        nested[tname] = prop
                        _walk_nested_props(prop["properties"])
                    end
                end
            elseif ptype == "array" && haskey(prop, "items")
                items = prop["items"]
                if items isa AbstractDict &&
                   get(items, "type", nothing) == "object" &&
                   haskey(items, "properties")
                    if haskey(nested_type_names, name)
                        tname = nested_type_names[name]
                        if !haskey(nested, tname)
                            nested[tname] = items
                            _walk_nested_props(items["properties"])
                        end
                    end
                end
            end
        end
    end

    for (_, schema) in schemas
        if haskey(schema, "properties")
            _walk_nested_props(schema["properties"])
        end
    end

    # Build field definitions for each nested type
    type_fields = Dict{Symbol,Any}()
    for (tname, schema_dict) in nested
        type_fields[tname] =
            struct_fields_from_schema(schema_dict, enum_lookup, nested_type_names)
    end

    # Topological sort: types that depend on other nested types come after
    ordered = Pair{Symbol,Any}[]
    remaining = copy(type_fields)
    placed = Set{Symbol}()

    while !isempty(remaining)
        progress = false
        for (tname, fields) in remaining
            deps = Set{Symbol}()
            for f in fields
                ft = f.type
                if ft isa Symbol && ft in keys(type_fields)
                    push!(deps, ft)
                elseif ft isa Expr && ft.head == :curly
                    inner = ft.args[2]
                    if inner isa Symbol && inner in keys(type_fields)
                        push!(deps, inner)
                    end
                end
            end
            if deps ⊆ placed
                push!(ordered, tname => fields)
                push!(placed, tname)
                delete!(remaining, tname)
                progress = true
            end
        end
        if !progress
            for (tname, fields) in remaining
                push!(ordered, tname => fields)
            end
            break
        end
    end

    return ordered
end

# ---------------------------------------------------------------------------
# Code generation via Core.eval
# ---------------------------------------------------------------------------

"""Generate an @enum type with JSON serialization in the given module."""
function generate_enum!(mod::Module, name::Symbol, members::Vector{Pair{Symbol,String}})
    member_syms = [m.first for m in members]
    fwd_name = Symbol("_", uppercase(string(name)), "_TO_STR")
    rev_name = Symbol("_STR_TO_", uppercase(string(name)))

    Core.eval(
        mod,
        Expr(:macrocall, Symbol("@enum"), LineNumberNode(0), name, member_syms...),
    )
    Core.eval(mod, Expr(:export, name, member_syms...))

    fwd_pairs = [:($(m.first) => $(m.second)) for m in members]
    Core.eval(mod, :(const $fwd_name = Dict{$name,String}($(fwd_pairs...))))

    rev_pairs = [:($(m.second) => $(m.first)) for m in members]
    Core.eval(mod, :(const $rev_name = Dict{String,$name}($(rev_pairs...))))

    # Base.string returns the OCPP wire value (used by JSON.lower default for Enums)
    Core.eval(mod, :(function Base.string(x::$name)
        return $fwd_name[x]
    end))
    # StructUtils.lift: deserialize string → enum
    Core.eval(mod, :(function StructUtils.lift(::Type{$name}, s::AbstractString)
        return $rev_name[String(s)]
    end))
    return nothing
end

"""Generate a @kwdef struct with JSON camelCase name mapping via StructUtils."""
function generate_struct!(mod::Module, name::Symbol, fields)
    field_exprs = Expr[]
    for f in fields
        jl_name = f.jl_name
        jl_type = f.type
        if f.required
            push!(field_exprs, :($jl_name::$jl_type))
        else
            push!(field_exprs, Expr(:(=), :($jl_name::Union{$jl_type,Nothing}), :nothing))
        end
    end

    struct_body = Expr(:block, field_exprs...)
    struct_expr = Expr(
        :macrocall,
        Expr(:., :Base, QuoteNode(Symbol("@kwdef"))),
        LineNumberNode(0),
        Expr(:struct, false, name, struct_body),
    )
    Core.eval(mod, struct_expr)

    Core.eval(mod, Expr(:export, name))

    # Empty structs need explicit structlike override for JSON serialization
    if isempty(fields)
        Core.eval(mod, :(StructUtils.structlike(::Type{$name}) = true))
    end

    # Build fieldtags for camelCase ↔ snake_case mapping
    name_pairs = Tuple{Symbol,String}[]
    for f in fields
        camel = f.json_name
        if Symbol(camel) != f.jl_name
            push!(name_pairs, (f.jl_name, camel))
        end
    end
    if !isempty(name_pairs)
        keys_tuple = Tuple(p[1] for p in name_pairs)
        vals_tuple = Tuple((json = (name = p[2],),) for p in name_pairs)
        tags_val = NamedTuple{keys_tuple}(vals_tuple)
        Core.eval(
            mod,
            :(StructUtils.fieldtags(::StructUtils.StructStyle, ::Type{$name}) = $tags_val),
        )
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

"""
    generate_types!(mod, schema_dir, enum_registry, nested_type_names, registry_name)

Read all OCPP JSON schemas from `schema_dir` and generate enums, structs,
and an action registry in the given module.

- `enum_registry`: sorted value vectors → (EnumTypeName, member_prefix)
- `nested_type_names`: JSON property name → Julia type name for shared sub-types
- `registry_name`: Symbol for the action registry constant (e.g. :V16_ACTIONS)
"""
function generate_types!(
    mod::Module,
    schema_dir::String,
    enum_registry::Dict{Vector{String},Tuple{Symbol,String}},
    nested_type_names::Dict{String,Symbol},
    registry_name::Symbol,
)
    schemas = read_schemas(schema_dir)

    # Build reverse lookup: sorted enum values → enum type name
    enum_lookup = Dict{Vector{String},Symbol}()
    for (values, (name, _)) in enum_registry
        enum_lookup[values] = name
    end

    # 1. Generate enums
    enum_defs = collect_enums(schemas, enum_registry)
    for (ename, members) in enum_defs
        generate_enum!(mod, ename, members)
    end

    # 2. Generate shared nested types (dependency-ordered)
    nested = collect_nested_types(schemas, enum_lookup, nested_type_names)
    for (tname, fields) in nested
        generate_struct!(mod, tname, fields)
    end

    # 3. Generate action payload structs
    action_names = String[]
    for (title, schema) in schemas
        struct_name = Symbol(title)
        if any(p -> p.first == struct_name, nested)
            continue
        end

        fields = struct_fields_from_schema(schema, enum_lookup, nested_type_names)
        generate_struct!(mod, struct_name, fields)

        base = if endswith(title, "Response")
            title[1:(end-8)]
        elseif endswith(title, "Request")
            title[1:(end-7)]
        else
            title
        end
        if base ∉ action_names
            push!(action_names, base)
        end
    end

    # 4. Generate action registry
    sort!(action_names)
    registry_pairs = Expr[]
    for action in action_names
        req_sym = Symbol(action * "Request")
        resp_sym = Symbol(action * "Response")
        push!(registry_pairs, :($action => (request = $req_sym, response = $resp_sym)))
    end

    Core.eval(
        mod,
        :(
            const $registry_name =
                Dict{String,@NamedTuple{request::DataType,response::DataType}}(
                    $(registry_pairs...),
                )
        ),
    )
    Core.eval(mod, :(export $registry_name, request_type, response_type))

    Core.eval(
        mod,
        :(
            function request_type(action::String)
                haskey($registry_name, action) ||
                    throw(ArgumentError("Unknown OCPP action: \$action"))
                return $registry_name[action].request
            end
        ),
    )
    Core.eval(
        mod,
        :(
            function response_type(action::String)
                haskey($registry_name, action) ||
                    throw(ArgumentError("Unknown OCPP action: \$action"))
                return $registry_name[action].response
            end
        ),
    )

    return nothing
end

# ===========================================================================
# V201-style schemas: types defined in "definitions" with $ref references
# ===========================================================================

"""Merge all `definitions` sections across schemas into one Dict."""
function merge_definitions(schemas)
    all_defs = Dict{String,Dict{String,Any}}()
    for (_, schema) in schemas
        defs = get(schema, "definitions", Dict{String,Any}())
        for (name, defn) in defs
            defn isa AbstractDict || continue
            if !haskey(all_defs, name)
                all_defs[name] = defn
            end
        end
    end
    return all_defs
end

"""
Derive a Julia type name from a v201 definition name.
"BootReasonEnumType" → :BootReason, "ChargingStationType" → :ChargingStation
"""
function _def_to_julia_name(def_name::String)
    if endswith(def_name, "EnumType")
        return Symbol(def_name[1:(end-8)])
    elseif endswith(def_name, "Type")
        return Symbol(def_name[1:(end-4)])
    else
        return Symbol(def_name)
    end
end

"""
Derive an enum member prefix from a v201 definition name.
"RegistrationStatusEnumType" → "Registration"
"BootReasonEnumType" → "BootReason"
"""
function _enum_prefix(def_name::String)
    base = replace(def_name, "EnumType" => "")
    if endswith(base, "Status")
        return base[1:(end-6)]
    end
    return base
end

"""
Resolve a property (which may contain `\$ref`) to a Julia type symbol.
`def_type_map` maps definition names to Julia type symbols.
"""
function _resolve_ref_type(
    prop::AbstractDict{String,Any},
    def_type_map::Dict{String,Symbol},
)
    if haskey(prop, "\$ref")
        ref = prop["\$ref"]::String
        def_name = last(split(ref, "/"))
        return get(def_type_map, def_name, :Any)
    end

    jtype = get(prop, "type", "string")
    if jtype == "string"
        return :String
    elseif jtype == "integer"
        return :Int
    elseif jtype == "number"
        return :Float64
    elseif jtype == "boolean"
        return :Bool
    elseif jtype == "array"
        items = get(prop, "items", Dict{String,Any}())
        if items isa AbstractDict
            if haskey(items, "\$ref")
                ref = items["\$ref"]::String
                def_name = last(split(ref, "/"))
                inner = get(def_type_map, def_name, :Any)
                return :(Vector{$inner})
            end
            item_type = get(items, "type", "string")
            if item_type == "string"
                return :(Vector{String})
            elseif item_type == "integer"
                return :(Vector{Int})
            end
        end
        return :(Vector{Any})
    elseif jtype == "object"
        return :(Dict{String,Any})
    end
    return :Any
end

"""Extract struct fields from a v201 schema/definition, resolving `\$ref`."""
function fields_from_ref_schema(
    schema::AbstractDict{String,Any},
    def_type_map::Dict{String,Symbol},
)
    props = get(schema, "properties", Dict{String,Any}())
    required_set = Set{String}(get(schema, "required", String[]))

    fields =
        NamedTuple{(:json_name, :jl_name, :type, :required),Tuple{String,Symbol,Any,Bool}}[]

    for (json_name, prop) in props
        prop isa AbstractDict || continue
        jl_name = Symbol(_camel_to_snake(json_name))
        jl_type = _resolve_ref_type(prop, def_type_map)
        is_required = json_name in required_set
        push!(
            fields,
            (
                json_name = json_name,
                jl_name = jl_name,
                type = jl_type,
                required = is_required,
            ),
        )
    end

    sort!(fields; by = f -> (!f.required, f.json_name))
    return fields
end

"""Topologically sort definition names so dependencies come first."""
function _topo_sort_defs(names::Vector{String}, all_defs::Dict{String,Dict{String,Any}})
    name_set = Set(names)
    deps = Dict{String,Set{String}}()
    for name in names
        deps[name] = Set{String}()
        defn = all_defs[name]
        props = get(defn, "properties", Dict{String,Any}())
        for (_, prop) in props
            prop isa AbstractDict || continue
            if haskey(prop, "\$ref")
                ref_name = last(split(prop["\$ref"]::String, "/"))
                if ref_name in name_set && ref_name != name
                    push!(deps[name], ref_name)
                end
            end
            if get(prop, "type", nothing) == "array"
                items = get(prop, "items", Dict{String,Any}())
                if items isa AbstractDict && haskey(items, "\$ref")
                    ref_name = last(split(items["\$ref"]::String, "/"))
                    if ref_name in name_set && ref_name != name
                        push!(deps[name], ref_name)
                    end
                end
            end
        end
    end

    ordered = String[]
    placed = Set{String}()
    remaining = Set(names)

    while !isempty(remaining)
        progress = false
        for name in sort(collect(remaining))
            if deps[name] ⊆ placed
                push!(ordered, name)
                push!(placed, name)
                delete!(remaining, name)
                progress = true
            end
        end
        if !progress
            append!(ordered, sort(collect(remaining)))
            break
        end
    end
    return ordered
end

"""
    generate_types_from_definitions!(mod, schema_dir, registry_name; ...)

Generate types from v201-style schemas that use `definitions` + `\$ref`.
Enum and type names are derived from definition names. Enum member prefixes
are auto-derived but can be overridden via `prefix_overrides`.
"""
function generate_types_from_definitions!(
    mod::Module,
    schema_dir::String,
    registry_name::Symbol;
    prefix_overrides::Dict{String,String} = Dict{String,String}(),
    skip_definitions::Set{String} = Set{String}(),
)
    schemas = read_schemas(schema_dir)
    all_defs = merge_definitions(schemas)

    # Separate enum definitions from object definitions
    enum_def_names = String[]
    object_def_names = String[]
    for (name, defn) in all_defs
        name in skip_definitions && continue
        if haskey(defn, "enum")
            push!(enum_def_names, name)
        elseif get(defn, "type", nothing) == "object" && haskey(defn, "properties")
            push!(object_def_names, name)
        end
    end
    sort!(enum_def_names)
    sort!(object_def_names)

    # Build def_name → Julia type name mapping (for $ref resolution)
    # Object types first, then enums (resolve collisions by keeping "Enum" suffix)
    def_type_map = Dict{String,Symbol}()
    obj_jl_names = Set{Symbol}()
    for name in object_def_names
        jl = _def_to_julia_name(name)
        def_type_map[name] = jl
        push!(obj_jl_names, jl)
    end
    for name in enum_def_names
        jl = _def_to_julia_name(name)
        if jl in obj_jl_names
            # Collision: keep "Enum" suffix (e.g. IdTokenEnumType → IdTokenEnum)
            jl = Symbol(replace(name, "EnumType" => "Enum", "Type" => ""))
        end
        def_type_map[name] = jl
    end

    # Detect which enum values appear in multiple enums (need prefixing)
    # Also detect values that shadow Base names
    _BASE_NAMES = Set([
        "string",
        "print",
        "show",
        "read",
        "write",
        "open",
        "close",
        "nothing",
        "missing",
        "true",
        "false",
        "Int",
        "Float64",
    ])
    value_count = Dict{String,Int}()
    for name in enum_def_names
        for v in all_defs[name]["enum"]
            sv = string(v)
            value_count[sv] = get(value_count, sv, 0) + 1
        end
    end

    # 1. Generate enums
    for def_name in enum_def_names
        jl_name = def_type_map[def_name]
        defn = all_defs[def_name]
        values = [string(v) for v in defn["enum"]]

        needs_prefix =
            any(v -> value_count[v] > 1, values) ||
            any(v -> _ocpp_string_to_identifier(v) in _BASE_NAMES, values)
        prefix = if haskey(prefix_overrides, def_name)
            prefix_overrides[def_name]
        elseif needs_prefix
            _enum_prefix(def_name)
        else
            ""
        end

        members = Pair{Symbol,String}[]
        for v in values
            member = _make_member_name(prefix, v)
            push!(members, member => v)
        end
        generate_enum!(mod, jl_name, members)
    end

    # 2. Generate object types (topologically sorted)
    sorted_obj_names = _topo_sort_defs(object_def_names, all_defs)
    for def_name in sorted_obj_names
        jl_name = def_type_map[def_name]
        defn = all_defs[def_name]
        fields = fields_from_ref_schema(defn, def_type_map)
        generate_struct!(mod, jl_name, fields)
    end

    # 3. Generate action payload structs
    action_names = String[]
    for (title, schema) in schemas
        struct_name = Symbol(title)
        fields = fields_from_ref_schema(schema, def_type_map)
        generate_struct!(mod, struct_name, fields)

        base = if endswith(title, "Response")
            title[1:(end-8)]
        elseif endswith(title, "Request")
            title[1:(end-7)]
        else
            title
        end
        if base ∉ action_names
            push!(action_names, base)
        end
    end

    # 4. Generate action registry
    sort!(action_names)
    registry_pairs = Expr[]
    for action in action_names
        req_sym = Symbol(action * "Request")
        resp_sym = Symbol(action * "Response")
        push!(registry_pairs, :($action => (request = $req_sym, response = $resp_sym)))
    end

    Core.eval(
        mod,
        :(
            const $registry_name =
                Dict{String,@NamedTuple{request::DataType,response::DataType}}(
                    $(registry_pairs...),
                )
        ),
    )
    Core.eval(mod, :(export $registry_name, request_type, response_type))

    Core.eval(
        mod,
        :(
            function request_type(action::String)
                haskey($registry_name, action) ||
                    throw(ArgumentError("Unknown OCPP action: \$action"))
                return $registry_name[action].request
            end
        ),
    )
    Core.eval(
        mod,
        :(
            function response_type(action::String)
                haskey($registry_name, action) ||
                    throw(ArgumentError("Unknown OCPP action: \$action"))
                return $registry_name[action].response
            end
        ),
    )

    return nothing
end
