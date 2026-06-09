# Limitations

> *"You can never know everything, and part of what you know is always wrong. Perhaps even the most important part. A portion of wisdom lies in knowing that. A portion of courage lies in going on anyway."*
>
> ― Robert Jordan, **Winter's Heart**

Cerulean is a hobby project with a small user base. The author started it without a full appreciation of how hard writing a correct formatter is.

The author used agentic coding extensively throughout development as a deliberate exercise in learning and improving this workflow on a real codebase.

## Known issues

Cerulean never silently drops a comment or writes unparseable code. It re-parses its own output and counts the comments; if the result is invalid Teal or a comment went missing, it keeps the original file and reports a skip:

    file.tl: formatting skipped: the formatter changed the number of comments (1 -> 0); left unchanged

Most skips come from an inline comment wedged between the tokens of one construct, such as `local --[[c]] x = 1` or `x as --[[c]] integer`, which Cerulean cannot yet reattach. Moving the comment to its own line formats the file. The fuzzer (`make fuzz`) mostly finds these cases; crashes and broken output are rare.

## Test coverage

Cerulean has been run against large, non-trivial Teal codebases without issues. The test suite has over 700 cases and covers a wide range of inputs.
