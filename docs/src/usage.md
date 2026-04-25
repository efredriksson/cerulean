# Usage

Format files in place:

```sh
ceru src/
ceru src/myfile.tl
```

Check whether files would be reformatted (exits 1 if any would change):

```sh
ceru --check src/
```

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--check` | off | Report files that would be reformatted; exit 1 if any |
| `--indent <n>` | `4` | Indentation width in spaces |
| `--line-length <n>` | `88` | Target line length |
| `--no-sort-requires` | — | Disable sorting of `require` statements |
