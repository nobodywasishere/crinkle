# Phase 20a — VS Code Extension (Detailed Plan)

## Objectives
- Create a minimal VS Code extension to test the LSP server.
- Enable real-world testing of LSP features as they're developed.
- Provide syntax highlighting for Jinja2 templates.

## Priority
**LOW** (but enables testing of all subsequent LSP phases)

## Scope (Phase 20a)
- Create VS Code extension scaffold.
- Implement LSP client integration.
- Add basic Jinja2 syntax highlighting via TextMate grammar.
- Package for local development use.

## File Structure
```
editors/
  vscode/
    package.json          # Extension manifest
    tsconfig.json         # TypeScript config
    src/
      extension.ts        # Extension entry point
    syntaxes/
      jinja.tmLanguage.json  # TextMate grammar for syntax highlighting
    language-configuration.json  # Bracket matching, comments, etc.
    README.md             # Usage instructions
```

## Features

### LSP Client
- Connect to `crinkle lsp` as the language server
- Pass through `--log` option for debugging
- Support `.j2`, `.jinja`, `.jinja2` file extensions

### Syntax Highlighting
- Jinja2 delimiters: `{{ }}`, `{% %}`, `{# #}`
- Keywords: `if`, `else`, `elif`, `endif`, `for`, `endfor`, `block`, `endblock`, etc.
- Filters and tests
- String literals and numbers
- Comments

### Language Configuration
- Bracket pairs for Jinja2 delimiters
- Comment toggling (`{# #}`)
- Auto-closing pairs

## API Design

### Extension Entry Point
```typescript
import * as vscode from 'vscode';
import { LanguageClient, LanguageClientOptions, ServerOptions } from 'vscode-languageclient/node';

let client: LanguageClient;

export function activate(context: vscode.ExtensionContext) {
  const config = vscode.workspace.getConfiguration('crinkle');
  const serverPath = config.get<string>('serverPath') || 'crinkle';
  const logFile = config.get<string>('logFile');

  const serverOptions: ServerOptions = {
    command: serverPath,
    args: ['lsp', ...(logFile ? ['--log', logFile, '--log-level', 'debug'] : [])]
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [
      { scheme: 'file', language: 'jinja' }
    ]
  };

  client = new LanguageClient('crinkle', 'Crinkle LSP', serverOptions, clientOptions);
  client.start();
}

export function deactivate(): Thenable<void> | undefined {
  return client?.stop();
}
```

### Package.json Configuration
```json
{
  "name": "crinkle-vscode",
  "displayName": "Crinkle - Jinja2 Support",
  "description": "Jinja2 template support powered by Crinkle LSP",
  "version": "0.1.0",
  "engines": { "vscode": "^1.75.0" },
  "categories": ["Programming Languages"],
  "activationEvents": ["onLanguage:jinja"],
  "main": "./out/extension.js",
  "contributes": {
    "languages": [{
      "id": "jinja",
      "aliases": ["Jinja2", "Jinja", "jinja2"],
      "extensions": [".j2", ".jinja", ".jinja2"],
      "configuration": "./language-configuration.json"
    }],
    "grammars": [{
      "language": "jinja",
      "scopeName": "text.html.jinja",
      "path": "./syntaxes/jinja.tmLanguage.json"
    }],
    "configuration": {
      "title": "Crinkle",
      "properties": {
        "crinkle.serverPath": {
          "type": "string",
          "default": "crinkle",
          "description": "Path to the crinkle binary"
        },
        "crinkle.logFile": {
          "type": "string",
          "default": "",
          "description": "Path to LSP log file (empty = no logging)"
        }
      }
    }
  }
}
```

## Acceptance Criteria
- Extension loads and connects to LSP server.
- Syntax highlighting works for Jinja2 constructs.
- Extension can be installed locally for development.
- LSP lifecycle (initialize/shutdown) works correctly.
- Document sync events trigger on file open/edit/close.

## Checklist
- [x] Create `editors/vscode/` directory structure
- [x] Create `package.json` with extension manifest
- [x] Create `tsconfig.json` for TypeScript compilation
- [x] Implement `extension.ts` with LSP client
- [x] Create TextMate grammar for Jinja2 syntax highlighting
- [x] Create `language-configuration.json` for editor features
- [x] Add npm scripts for building and packaging
- [x] Test extension with local crinkle binary
- [x] Document installation and usage in README.md

## Development Workflow
```bash
# Build crinkle
shards build

# Install extension dependencies
cd editors/vscode
npm install

# Compile TypeScript
npm run compile

# Launch VS Code with extension
code --extensionDevelopmentPath=$PWD
```

## Testing Notes
- Use `--log /tmp/crinkle-lsp.log --log-level debug` to see LSP messages
- Check Output panel in VS Code for client-side logs
- Test with various `.j2` files to verify syntax highlighting
