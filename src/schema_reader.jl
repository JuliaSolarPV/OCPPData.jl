"""
Read OCPP JSON schema files and generate Julia types at compile time via macros.

The two OCPP schema formats (V16 flat schemas, V201 `definitions` + `\$ref`)
differ only in how a property resolves to a Julia type. Everything else — field
extraction, enum AST, struct AST, registry AST, topo sort — is shared.

Each OCPP version provides a `resolve_type(prop, field_name)` function and
calls a macro that reads schemas at macro-expansion time and splices all
type definitions into the calling module.
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

"""Convert camelCase to snake_case."""
function _camel_to_snake(s::String)::String
    result = replace(s, r"([a-z0-9])([A-Z])" => s"\1_\2")
    return lowercase(result)
end

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
    if startswith(clean, prefix)
        return Symbol(clean)
    end
    return Symbol(prefix, clean)
end

"""Strip Request/Response suffix to get base action name."""
function _strip_request_response(title::String)
    if endswith(title, "Response")
        return title[1:(end-8)]
    elseif endswith(title, "Request")
        return title[1:(end-7)]
    end
    return title
end

"""Names from Base that enum members must not shadow."""
const _BASE_NAMES = Set([
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

# ---------------------------------------------------------------------------
# Unified type resolution
# ---------------------------------------------------------------------------

"""
    _resolve_type(prop, lookup_fn) -> Symbol or Expr

Resolve a JSON schema property to a Julia type expression. `lookup_fn(prop)`
handles version-specific lookups (inline enums, nested types, `\$ref`);
shared primitive/array/object logic lives here.
"""
function _resolve_type(prop::AbstractDict{String,Any}, lookup_fn)
    result = lookup_fn(prop)
    result !== nothing && return result

    jtype = get(prop, "type", "string")
    pt = _primitive_type(jtype)
    pt !== nothing && return pt

    if jtype == "array"
        items = get(prop, "items", Dict{String,Any}())
        if items isa AbstractDict
            inner = lookup_fn(items)
            if inner !== nothing
                return :(Vector{$inner})
            end
            ipt = _primitive_type(get(items, "type", "string"))
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

# ---------------------------------------------------------------------------
# Unified field extraction
# ---------------------------------------------------------------------------

"""
    extract_fields(schema, resolve_type_fn) -> Vector{FieldDef}

Extract field definitions from a JSON schema. `resolve_type_fn(prop, name)`
maps each property to a Julia type — this is the single point of variation
between V16 and V201.
"""
function extract_fields(schema::AbstractDict{String,Any}, resolve_type_fn)
    props = get(schema, "properties", Dict{String,Any}())
    required_set = Set{String}(get(schema, "required", String[]))

    fields =
        NamedTuple{(:json_name, :jl_name, :type, :required),Tuple{String,Symbol,Any,Bool}}[]

    for (json_name, prop) in props
        prop isa AbstractDict || continue
        jl_name = Symbol(_camel_to_snake(json_name))
        jl_type = resolve_type_fn(prop, json_name)
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

# ---------------------------------------------------------------------------
# Generic schema property walker
# ---------------------------------------------------------------------------

"""
    walk_properties(fn, props)

Recursively walk JSON schema properties, calling `fn(name, prop)` for each.
Descends into nested objects and array items that are objects.
"""
function walk_properties(fn, props)
    for (name, prop) in props
        prop isa AbstractDict || continue
        fn(name, prop)
        if get(prop, "type", nothing) == "object" && haskey(prop, "properties")
            walk_properties(fn, prop["properties"])
        elseif get(prop, "type", nothing) == "array" && haskey(prop, "items")
            items = prop["items"]
            if items isa AbstractDict &&
               get(items, "type", nothing) == "object" &&
               haskey(items, "properties")
                walk_properties(fn, items["properties"])
            end
        end
    end
end

# ---------------------------------------------------------------------------
# AST builders
# ---------------------------------------------------------------------------

const _GENERATED_SOURCE = LineNumberNode(0, Symbol(@__FILE__))

"""Build AST for an @enum type with JSON serialization support."""
function enum_expr(name::Symbol, members::Vector{Pair{Symbol,String}})::Expr
    member_syms = [m.first for m in members]
    fwd_name = Symbol("_", uppercase(string(name)), "_TO_STR")
    rev_name = Symbol("_STR_TO_", uppercase(string(name)))

    fwd_pairs = [:($(m.first) => $(m.second)) for m in members]
    rev_pairs = [:($(m.second) => $(m.first)) for m in members]

    return Expr(
        :block,
        Expr(:macrocall, Symbol("@enum"), _GENERATED_SOURCE, name, member_syms...),
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

    push!(
        exprs,
        Expr(
            :macrocall,
            Expr(:., :Base, QuoteNode(Symbol("@kwdef"))),
            _GENERATED_SOURCE,
            Expr(:struct, false, name, Expr(:block, field_exprs...)),
        ),
    )
    push!(exprs, Expr(:export, name))

    if isempty(fields)
        push!(exprs, :(StructUtils.structlike(::Type{$name}) = true))
    end

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
# Shared codegen pipeline
# ---------------------------------------------------------------------------

"""
    _build_all_exprs(enums, sorted_types, action_schemas, resolve_type_fn, registry_name)

Shared codegen: emit enum AST, struct AST for sub-types, struct AST for
action payloads, and registry AST. Both macros funnel into this.
"""
function _build_all_exprs(
    enums,
    sorted_types_with_fields,
    action_schemas,
    resolve_type_fn,
    registry_name::Symbol;
    skip_names::Set{Symbol} = Set{Symbol}(),
)
    exprs = Expr[]

    for (name, members) in enums
        push!(exprs, enum_expr(name, members))
    end

    for (name, fields) in sorted_types_with_fields
        push!(exprs, struct_expr(name, fields))
    end

    action_names = String[]
    for (title, schema) in action_schemas
        sname = Symbol(title)
        sname in skip_names && continue
        push!(exprs, struct_expr(sname, extract_fields(schema, resolve_type_fn)))
        base = _strip_request_response(title)
        if base ∉ action_names
            push!(action_names, base)
        end
    end

    push!(exprs, registry_expr(action_names, registry_name))
    return exprs
end

# ---------------------------------------------------------------------------
# V16 macro
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

    # V16 type resolver: check inline enums, then nested type names, then primitives
    resolve =
        (prop, field_name) -> _resolve_type(
            prop,
            function (p)
                if haskey(p, "enum")
                    values = sort(String[string(v) for v in p["enum"]])
                    if haskey(enum_lookup, values)
                        return enum_lookup[values]
                    end
                    return :String
                end
                if get(p, "type", nothing) == "object" &&
                   haskey(nested_type_names, field_name)
                    return nested_type_names[field_name]
                end
                return nothing
            end,
        )

    # Collect enums by walking all schema properties
    seen = Set{Vector{String}}()
    enum_defs = Pair{Symbol,Vector{Pair{Symbol,String}}}[]
    for (_, schema) in schemas
        haskey(schema, "properties") || continue
        walk_properties(schema["properties"]) do _, prop
            haskey(prop, "enum") || return
            values = sort(String[string(v) for v in prop["enum"]])
            values in seen && return
            push!(seen, values)
            haskey(enum_registry, values) || return
            enum_name, prefix = enum_registry[values]
            members = Pair{Symbol,String}[]
            for v in prop["enum"]
                sv = string(v)
                push!(members, _make_member_name(prefix, sv) => sv)
            end
            push!(enum_defs, enum_name => members)
        end
    end

    # Collect nested types by walking all schema properties
    nested_schemas = Dict{Symbol,Any}()
    for (_, schema) in schemas
        haskey(schema, "properties") || continue
        walk_properties(schema["properties"]) do name, prop
            haskey(nested_type_names, name) || return
            tname = nested_type_names[name]
            haskey(nested_schemas, tname) && return
            ptype = get(prop, "type", nothing)
            if ptype == "object" && haskey(prop, "properties")
                nested_schemas[tname] = prop
            elseif ptype == "array" && haskey(prop, "items")
                items = prop["items"]
                if items isa AbstractDict &&
                   get(items, "type", nothing) == "object" &&
                   haskey(items, "properties")
                    nested_schemas[tname] = items
                end
            end
        end
    end

    # Build fields and topo-sort nested types
    nested_fields = Dict{Symbol,Any}()
    for (tname, schema_dict) in nested_schemas
        nested_fields[tname] = extract_fields(schema_dict, resolve)
    end
    all_nested = Set(keys(nested_fields))
    sorted_nested = _topo_sort(collect(keys(nested_fields))) do tname
        deps = Set{Symbol}()
        for f in nested_fields[tname]
            ft = f.type
            if ft isa Symbol && ft in all_nested
                push!(deps, ft)
            elseif ft isa Expr && ft.head == :curly
                inner = ft.args[2]
                if inner isa Symbol && inner in all_nested
                    push!(deps, inner)
                end
            end
        end
        return deps
    end
    sorted_types = [name => nested_fields[name] for name in sorted_nested]

    exprs = _build_all_exprs(
        enum_defs,
        sorted_types,
        collect(schemas),
        resolve,
        registry_name;
        skip_names = all_nested,
    )
    return esc(Expr(:block, exprs...))
end

# ---------------------------------------------------------------------------
# V201 helpers
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# V201 macro
# ---------------------------------------------------------------------------

"""
    @generate_ocpp_types_from_definitions schema_dir registry_name

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

    # V201 type resolver: check $ref, then fall back to primitives
    resolve =
        (prop, _) -> _resolve_type(prop, function (p)
            if haskey(p, "\$ref")
                ref = p["\$ref"]::String
                def_name = last(split(ref, "/"))
                return get(def_type_map, def_name, :Any)
            end
            return nothing
        end)

    # Detect which enum values need prefixing
    value_count = Dict{String,Int}()
    for name in enum_def_names
        for v in all_defs[name]["enum"]
            sv = string(v)
            value_count[sv] = get(value_count, sv, 0) + 1
        end
    end
    all_type_names = Set{String}()
    for (_, jl) in def_type_map
        push!(all_type_names, string(jl))
    end
    for (title, _) in schemas
        push!(all_type_names, title)
    end

    # Build enum definitions
    enum_defs = Pair{Symbol,Vector{Pair{Symbol,String}}}[]
    for def_name in enum_def_names
        jl_name = def_type_map[def_name]
        values = [string(v) for v in all_defs[def_name]["enum"]]

        needs_prefix =
            any(v -> value_count[v] > 1, values) ||
            any(v -> _ocpp_string_to_identifier(v) in _BASE_NAMES, values) ||
            any(v -> _ocpp_string_to_identifier(v) in all_type_names, values)
        prefix = needs_prefix ? _enum_prefix(def_name) : ""

        members = Pair{Symbol,String}[]
        for v in values
            push!(members, _make_member_name(prefix, v) => v)
        end
        push!(enum_defs, jl_name => members)
    end

    # Topo-sort object types by $ref dependencies
    name_set = Set(object_def_names)
    sorted_obj_names = _topo_sort(object_def_names) do name
        deps = Set{String}()
        props = get(all_defs[name], "properties", Dict{String,Any}())
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

    sorted_types = Pair{Symbol,Any}[]
    for def_name in sorted_obj_names
        jl_name = def_type_map[def_name]
        fields = extract_fields(all_defs[def_name], resolve)
        push!(sorted_types, jl_name => fields)
    end

    exprs =
        _build_all_exprs(enum_defs, sorted_types, collect(schemas), resolve, registry_name)
    return esc(Expr(:block, exprs...))
end
