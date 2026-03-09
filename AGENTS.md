# Local Agent Notes

## Environment

- Run `source .envrc` from the repo root before using `mix` if the shell does not already have Elixir and Erlang on `PATH`.
- Each example app under `examples/` has its own `.envrc` that sources the root file, so `source .envrc` works there too.
- If you still cannot resolve `mix` or `erl`, prepend:
  `export PATH=/home/abhishek/.local/share/mise/installs/elixir/1.18.4/bin:/home/abhishek/.local/share/mise/installs/erlang/27.3.4/bin:$PATH`

## Examples

- `examples/ash_persistence/priv/` is generated runtime output and should not be committed.
