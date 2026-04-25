# Limitations

> *“You can never know everything, and part of what you know is always wrong. Perhaps even the most important part. A portion of wisdom lies in knowing that. A portion of courage lies in going on anyway.”*
>
> ― Robert Jordan, **Winter's Heart**

Cerulean is experimental. The output format may change between versions. Use it at your own risk — always review diffs before committing formatted code.

## Known issues

The following behaviours are not yet correctly handled. They are tracked as pending tests in the test suite.

**Comments in wrapped expressions are dropped.**
When an expression is split across multiple lines, inline comments within it may be lost in the output.

**Expressions with table types may be reformatted incorrectly.**
An expression whose type annotation is a table type can produce malformed output in some cases.

**`-- fmt: off` after a comment on the same line still reformats that comment.**
If `-- fmt: off` appears on the same line as another comment, the formatter still processes that line rather than treating it as the start of an excluded region.
