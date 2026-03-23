"""
Read OCPP JSON schema files and generate Julia types at compile time via macros.

Version-agnostic logic for:
- Reading JSON schema files
- Extracting enum value sets and building @enum AST
- Extracting struct field definitions and building @kwdef struct AST
- Building action registries

Each OCPP version provides its own registry/config, then calls a macro
(`@generate_ocpp_types` or `@generate_ocpp_types_from_definitions`) that
reads schemas at macro-expansion time and splices all type definitions
into the calling module.
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
# Shared helpers
# ---------------------------------------------------------------------------

"""Map a JSON schema type string to a Julia type symbol, or `nothing` for compound types."""
function _primitive_type(jtype::String)
    jtype == "string" && return :String
    jtype == "integer" && return :Int
    jtype == "number" && return :Float64
    jtype == "boolean" && return :Bool
    return nothing
end

"""
    _topo_sort(deps_fn, items) -> Vector

Topologically sort `items` so that dependencies (returned by `deps_fn(item)`)
come before dependents. Falls back to sorted order for cycles.
"""
function _topo_sort(deps_fn, items::Vector{T})::Vector{T} where {T}
    dep_map = Dict{T,Set{T}}()
    for item in items
        dep_map[item] = deps_fn(item)
    end

    ordered = T[]
    placed = Set{T}()
    remaining = Set{T}(items)

    while !isempty(remaining)
        progress = false
        for item in sort(collect(remaining))
            if dep_map[item] ⊆ placed
                push!(ordered, item)
                push!(placed, item)
                delete!(remaining, item)
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

"""Map a JSON schema property to a Julia type expression (V16 flat schemas)."""
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
    pt = _primitive_type(jtype)
    pt !== nothing && return pt

    if jtype == "object"
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
            end
            ipt = _primitive_type(item_type)
            if ipt !== nothing
                return :(Vector{$ipt})
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

    # Topological sort using shared helper
    all_keys = Set(keys(type_fields))
    sorted_names = _topo_sort(collect(keys(type_fields))) do tname
        deps = Set{Symbol}()
        for f in type_fields[tname]
            ft = f.type
            if ft isa Symbol && ft in all_keys
                push!(deps, ft)
            elseif ft isa Expr && ft.head == :curly
                inner = ft.args[2]
                if inner isa Symbol && inner in all_keys
                    push!(deps, inner)
                end
            end
        end
        return deps
    end

    return [name => type_fields[name] for name in sorted_names]
end

# ---------------------------------------------------------------------------
# AST builders (replace Core.eval with returned Expr)
# ---------------------------------------------------------------------------

"""Build AST for an @enum type with JSON serialization support."""
function enum_expr(name::Symbol, members::Vector{Pair{Symbol,String}})::Expr
    member_syms = [m.first for m in members]
    fwd_name = Symbol("_", uppercase(string(name)), "_TO_STR")
    rev_name = Symbol("_STR_TO_", uppercase(string(name)))

    fwd_pairs = [:($(m.first) => $(m.second)) for m in members]
    rev_pairs = [:($(m.second) => $(m.first)) for m in members]

    return Expr(
        :block,
        Expr(:macrocall, Symbol("@enum"), LineNumberNode(0), name, member_syms...),
        Expr(:export, name, member_syms...),
        :(const $fwd_name = Dict{$name,String}($(fwd_pairs...))),
        :(const $rev_name = Dict{String,$name}($(rev_pairs...))),
        :(function Base.string(x::$name)
            return $fwd_name[x]
        end),
        :(function StructUtils.lift(::Type{$name}, s::AbstractString)
            return $rev_name[String(s)]
        end),
    )
end

"""Build AST for a @kwdef struct with JSON camelCase name mapping via StructUtils."""
function struct_expr(name::Symbol, fields)::Expr
    exprs = Expr[]

    # Build field expressions
    field_exprs = Expr[]
    for f in fields
        if f.required
            push!(field_exprs, :($(f.jl_name)::$(f.type)))
        else
            push!(
                field_exprs,
                Expr(:(=), :($(f.jl_name)::Union{$(f.type),Nothing}), :nothing),
            )
        end
    end

    # @kwdef struct
    push!(
        exprs,
        Expr(
            :macrocall,
            Expr(:., :Base, QuoteNode(Symbol("@kwdef"))),
            LineNumberNode(0),
            Expr(:struct, false, name, Expr(:block, field_exprs...)),
        ),
    )

    # export
    push!(exprs, Expr(:export, name))

    # Empty structs need explicit structlike override for JSON serialization
    if isempty(fields)
        push!(exprs, :(StructUtils.structlike(::Type{$name}) = true))
    end

    # Build fieldtags for camelCase ↔ snake_case mapping
    name_pairs = Tuple{Symbol,String}[]
    for f in fields
        if Symbol(f.json_name) != f.jl_name
            push!(name_pairs, (f.jl_name, f.json_name))
        end
    end
    if !isempty(name_pairs)
        keys_tuple = Tuple(p[1] for p in name_pairs)
        vals_tuple = Tuple((json = (name = p[2],),) for p in name_pairs)
        tags_val = NamedTuple{keys_tuple}(vals_tuple)
        push!(
            exprs,
            :(StructUtils.fieldtags(::StructUtils.StructStyle, ::Type{$name}) = $tags_val),
        )
    end

    return Expr(:block, exprs...)
end

"""Build AST for an action registry with request_type/response_type accessors."""
function registry_expr(action_names::Vector{String}, registry_name::Symbol)::Expr
    sort!(action_names)
    registry_pairs = Expr[]
    for action in action_names
        req_sym = Symbol(action * "Request")
        resp_sym = Symbol(action * "Response")
        push!(registry_pairs, :($action => (request = $req_sym, response = $resp_sym)))
    end

    return Expr(
        :block,
        :(
            const $registry_name =
                Dict{String,@NamedTuple{request::DataType,response::DataType}}(
                    $(registry_pairs...),
                )
        ),
        Expr(:export, registry_name, :request_type, :response_type),
        :(
            function request_type(action::String)
                haskey($registry_name, action) ||
                    throw(ArgumentError("Unknown OCPP action: \$action"))
                return $registry_name[action].request
            end
        ),
        :(
            function response_type(action::String)
                haskey($registry_name, action) ||
                    throw(ArgumentError("Unknown OCPP action: \$action"))
                return $registry_name[action].response
            end
        ),
    )
end

# ---------------------------------------------------------------------------
# Strip Request/Response suffix to get base action name
# ---------------------------------------------------------------------------

function _strip_request_response(title::String)
    if endswith(title, "Response")
        return title[1:(end-8)]
    elseif endswith(title, "Request")
        return title[1:(end-7)]
    end
    return title
end

# ---------------------------------------------------------------------------
# Macros: compile-time type generation
# ---------------------------------------------------------------------------

"""
    @generate_ocpp_types schema_dir enum_registry nested_type_names registry_name

Read V16-style OCPP JSON schemas at macro-expansion time and splice all
enum, struct, and registry definitions into the calling module.
"""
macro generate_ocpp_types(
    schema_dir_expr,
    enum_registry_expr,
    nested_type_names_expr,
    registry_name_expr,
)
    schema_dir = Core.eval(__module__, schema_dir_expr)
    enum_registry = Core.eval(__module__, enum_registry_expr)
    nested_type_names = Core.eval(__module__, nested_type_names_expr)
    registry_name = Core.eval(__module__, registry_name_expr)

    schemas = read_schemas(schema_dir)

    # Build reverse lookup: sorted enum values → enum type name
    enum_lookup = Dict{Vector{String},Symbol}()
    for (values, (name, _)) in enum_registry
        enum_lookup[values] = name
    end

    exprs = Expr[]

    # 1. Enums
    enum_defs = collect_enums(schemas, enum_registry)
    for (ename, members) in enum_defs
        push!(exprs, enum_expr(ename, members))
    end

    # 2. Nested types (dependency-ordered)
    nested = collect_nested_types(schemas, enum_lookup, nested_type_names)
    for (tname, fields) in nested
        push!(exprs, struct_expr(tname, fields))
    end

    # 3. Action payload structs
    action_names = String[]
    for (title, schema) in schemas
        sname = Symbol(title)
        if any(p -> p.first == sname, nested)
            continue
        end
        fields = struct_fields_from_schema(schema, enum_lookup, nested_type_names)
        push!(exprs, struct_expr(sname, fields))
        base = _strip_request_response(title)
        if base ∉ action_names
            push!(action_names, base)
        end
    end

    # 4. Registry
    push!(exprs, registry_expr(action_names, registry_name))

    return esc(Expr(:block, exprs...))
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
    pt = _primitive_type(jtype)
    pt !== nothing && return pt

    if jtype == "array"
        items = get(prop, "items", Dict{String,Any}())
        if items isa AbstractDict
            if haskey(items, "\$ref")
                ref = items["\$ref"]::String
                def_name = last(split(ref, "/"))
                inner = get(def_type_map, def_name, :Any)
                return :(Vector{$inner})
            end
            item_type = get(items, "type", "string")
            ipt = _primitive_type(item_type)
            if ipt !== nothing
                return :(Vector{$ipt})
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

"""
    @generate_ocpp_types_from_definitions schema_dir registry_name [prefix_overrides] [skip_definitions]

Read V201-style OCPP JSON schemas (with `definitions` + `\$ref`) at
macro-expansion time and splice all type definitions into the calling module.
"""
macro generate_ocpp_types_from_definitions(schema_dir_expr, registry_name_expr)
    schema_dir = Core.eval(__module__, schema_dir_expr)
    registry_name = Core.eval(__module__, registry_name_expr)

    schemas = read_schemas(schema_dir)
    all_defs = merge_definitions(schemas)

    # Separate enum definitions from object definitions
    enum_def_names = String[]
    object_def_names = String[]
    for (name, defn) in all_defs
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
            jl = Symbol(replace(name, "EnumType" => "Enum", "Type" => ""))
        end
        def_type_map[name] = jl
    end

    # Detect which enum values appear in multiple enums (need prefixing)
    # Also detect values that shadow Base names or collide with type names
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

    # Collect all type names so enum members don't shadow them
    all_type_names = Set{String}()
    for (_, jl) in def_type_map
        push!(all_type_names, string(jl))
    end
    for (title, _) in schemas
        push!(all_type_names, title)
    end

    exprs = Expr[]

    # 1. Enums
    for def_name in enum_def_names
        jl_name = def_type_map[def_name]
        defn = all_defs[def_name]
        values = [string(v) for v in defn["enum"]]

        needs_prefix =
            any(v -> value_count[v] > 1, values) ||
            any(v -> _ocpp_string_to_identifier(v) in _BASE_NAMES, values) ||
            any(v -> _ocpp_string_to_identifier(v) in all_type_names, values)
        prefix = if needs_prefix
            _enum_prefix(def_name)
        else
            ""
        end

        members = Pair{Symbol,String}[]
        for v in values
            member = _make_member_name(prefix, v)
            push!(members, member => v)
        end
        push!(exprs, enum_expr(jl_name, members))
    end

    # 2. Object types (topologically sorted)
    name_set = Set(object_def_names)
    sorted_obj_names = _topo_sort(object_def_names) do name
        deps = Set{String}()
        defn = all_defs[name]
        props = get(defn, "properties", Dict{String,Any}())
        for (_, prop) in props
            prop isa AbstractDict || continue
            if haskey(prop, "\$ref")
                ref_name = last(split(prop["\$ref"]::String, "/"))
                if ref_name in name_set && ref_name != name
                    push!(deps, ref_name)
                end
            end
            if get(prop, "type", nothing) == "array"
                items = get(prop, "items", Dict{String,Any}())
                if items isa AbstractDict && haskey(items, "\$ref")
                    ref_name = last(split(items["\$ref"]::String, "/"))
                    if ref_name in name_set && ref_name != name
                        push!(deps, ref_name)
                    end
                end
            end
        end
        return deps
    end

    for def_name in sorted_obj_names
        jl_name = def_type_map[def_name]
        defn = all_defs[def_name]
        fields = fields_from_ref_schema(defn, def_type_map)
        push!(exprs, struct_expr(jl_name, fields))
    end

    # 3. Action payload structs
    action_names = String[]
    for (title, schema) in schemas
        fields = fields_from_ref_schema(schema, def_type_map)
        push!(exprs, struct_expr(Symbol(title), fields))
        base = _strip_request_response(title)
        if base ∉ action_names
            push!(action_names, base)
        end
    end

    # 4. Registry
    push!(exprs, registry_expr(action_names, registry_name))

    return esc(Expr(:block, exprs...))
end
