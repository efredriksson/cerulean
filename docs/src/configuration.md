# Configuration

Options can be set project-wide in `tlconfig.lua` under a `cerulean` key. CLI flags override config file values.

```lua
return {
   cerulean = {
      indent_width = 2,
      max_line_width = 100,
      sort_requires = false,
   },
}
```

| Key | Default | Description |
|-----|---------|-------------|
| `indent_width` | `4` | Indentation width in spaces |
| `max_line_width` | `88` | Target line length |
| `sort_requires` | `true` | Sort `require` statements alphabetically |
