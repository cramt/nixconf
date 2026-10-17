
## On this machine: CLI only, no MCP server

REA is installed by Nix as the `rea` CLI on PATH, with Ghidra already wired in.
No MCP server is registered, and that is deliberate: its 207 tool schemas cost
75K context tokens per session. Ignore the MCP registration, `doctor` and
`setup` steps below, and never run `rea setup`, `rea update`, `rea mcp` or
`npx rea-agents`. Nix owns the installation.

Every MCP tool named below has a CLI command of the same name in kebab-case:
`inspect_artifact` is `rea inspect-artifact`, `open_binary` targets are given
as the first argument of each command. Run `rea <command> --help` (or
`--schema`) for its arguments, and pass `--format json` to get the Evidence
record. `rea --help` lists every command.
