# Roadmap

## Current Direction

The library is standardizing on Reactor-native durable steps:

- users write ordinary Reactor steps
- replayable durability is the default
- resumable behavior is expressed with `resume/4` on the step module

This keeps the public model close to Reactor while the durable runtime stays at
the step boundary.

## Near Term

1. Keep resumability on ordinary step modules through `resume/4`.
2. Keep the persistence contract explicit and step-local.
3. Keep examples and docs aligned with the Reactor-native model.

## Later DSL Work

The likely next DSL addition is an explicit step durability mode, for example:

```elixir
step :approval, MyApp.ApprovalStep do
  mode :resumable
end
```

That would be a convenience layer over the current runtime, not a new execution
model.

## Non-Goal Right Now

We are not introducing a second agent DSL. The immediate focus is a clean,
consistent Reactor-native API.
