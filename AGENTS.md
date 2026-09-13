# Repository instructions

## Graphify knowledge graph

- `graphify-out/graph.json` is a generated local code index and is ignored by
  Git. Use the Graphify MCP tools before broad cross-file, architecture, call
  path, or change-impact exploration when the graph exists.
- Pass this repository's absolute root as `project_path`, then verify relevant
  Lua source before editing.
- After changing supported Lua, shell, or JSON source, refresh the graph with
  `graphify-project update .` before handoff. Graph refreshes do not replace the
  repository's normal tests and validation.
