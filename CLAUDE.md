# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OCPP.jl is a Julia package implementing the Open Charge Point Protocol (OCPP). It is currently in early development, initialized from BestieTemplate.jl. The module lives in `src/OCPP.jl`.

## Common Commands

```bash
# Format code (JuliaFormatter)
julia -e 'using JuliaFormatter; format(".")'

# Build and serve docs locally
julia --project=docs -e "using LiveServer; serve(dir=\"docs/build\")"
# Or build docs:
julia --project=docs docs/make.jl
```

For test commands (run all, run single file, filter by tag), see the `julia-development` skill.

## Code Style

JuliaFormatter is enforced in CI. Config in `.JuliaFormatter.toml`:
- Indent: 4 spaces
- Line margin: 92 characters
- Unix line endings

## CI Workflows

- **Test**: Runs on push to `main` and all tags. Matrix: Julia LTS + v1, Ubuntu/macOS/Windows, x64.
- **Lint**: JuliaFormatter + pre-commit hooks (YAML/JSON/Markdown/CFF validation, link checker).
- **Docs**: Triggered by changes in `docs/`, `src/`, or `.toml` files. Runs doctests and deploys.

Pre-commit hooks are also configured locally via `.pre-commit-config.yaml`.

## Architecture Notes

The package is a single module (`module OCPP` in `src/OCPP.jl`). As OCPP protocol features are added, expect the module to grow with sub-modules or additional files `include`d from `src/OCPP.jl`. All public functions should have docstrings — they are auto-collected into `docs/src/95-reference.md` by Documenter.jl.
