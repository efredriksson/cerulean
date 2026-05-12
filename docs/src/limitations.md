# Limitations

> *"You can never know everything, and part of what you know is always wrong. Perhaps even the most important part. A portion of wisdom lies in knowing that. A portion of courage lies in going on anyway."*
>
> ― Robert Jordan, **Winter's Heart**

Cerulean is a hobby project with a small user base. The author started it without a full appreciation of how hard writing a correct formatter is.

The project has used agentic coding extensively throughout development. This was done as a deliberate exercise in learning how to use that workflow well on a real codebase.

## Known issues

The fuzzer (`make fuzz`) still finds idempotency failures: formatting the output of the formatter a second time sometimes produces a different result. On the other hand, the fuzzer rarely finds crashes, broken output, or cases where the formatter silently produces unparseable code. Those failure modes appear to now be uncommon.

## Test coverage

The formatter has been run against large, non-trivial Teal codebases without issues. The test suite has over 500 cases and covers a wide range of inputs.
