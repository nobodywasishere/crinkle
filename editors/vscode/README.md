# Crinkle VS Code Extension

Jinja2 template support for VS Code, powered by the Crinkle LSP server.

## Features

- **Syntax Highlighting**: Full syntax highlighting for Jinja2 templates
- **LSP Integration**: Real-time diagnostics and language features via Crinkle LSP
- **File Support**: `.j2`, `.jinja`, `.jinja2` extensions

## Requirements

- VS Code 1.75.0 or later
- Crinkle binary (`crinkle lsp` command must be available)

## Installation (Development)

1. Build the Crinkle binary:
   ```bash
   cd /path/to/crinkle
   shards build
   ```

2. Install extension dependencies:
   ```bash
   cd editors/vscode
   npm install
   ```

3. Compile the extension:
   ```bash
   npm run compile
   ```

4. Launch VS Code with the extension:
   ```bash
   code --extensionDevelopmentPath=$PWD
   ```

## Configuration

| Setting | Description | Default |
|---------|-------------|---------|
| `crinkle.serverPath` | Path to the crinkle binary (searches PATH if not absolute) | `crinkle` |
| `crinkle.logLevel` | Log level: debug, info, warning, error | `info` |
| `crinkle.trace.server` | Trace LSP communication: off, messages, verbose | `off` |

### Example Configuration

**For development** (before installing to PATH):
```json
{
  "crinkle.serverPath": "/absolute/path/to/crinkle/bin/crinkle",
  "crinkle.logLevel": "debug"
}
```

**For production** (after installing to PATH):
```json
{
  "crinkle.logLevel": "info"
}
```

> **Note**: The extension searches for `crinkle` in your system PATH by default. During development, specify the absolute path to `bin/crinkle` in your settings.

## Development

### Building

```bash
npm run compile   # Compile TypeScript
npm run watch     # Watch mode for development
```

### Packaging

```bash
npm run package   # Create .vsix package
```

### Debugging

1. Open the Output panel in VS Code (View > Output)
2. Select "Crinkle LSP" from the dropdown
3. Set `crinkle.logLevel` to `debug` for verbose logging
4. Set `crinkle.trace.server` to `verbose` to see LSP message traffic

## Syntax Highlighting

The extension provides syntax highlighting for:

- Jinja2 delimiters: `{{ }}`, `{% %}`, `{# #}`
- Keywords: `if`, `else`, `elif`, `endif`, `for`, `endfor`, `block`, `endblock`, etc.
- Filters and tests
- String literals and numbers
- Comments
- Embedded HTML

## License

MIT
