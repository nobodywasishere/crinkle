import * as vscode from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from 'vscode-languageclient/node';

let client: LanguageClient | undefined;
let outputChannel: vscode.OutputChannel | undefined;

export function activate(context: vscode.ExtensionContext) {
  const config = vscode.workspace.getConfiguration('crinkle');
  const serverPath = config.get<string>('serverPath') || 'crinkle';
  const logLevel = config.get<string>('logLevel') || 'info';

  // Create output channel for LSP logs
  outputChannel = vscode.window.createOutputChannel('Crinkle LSP');
  context.subscriptions.push(outputChannel);

  const args = ['lsp', '--log-level', logLevel];

  const serverOptions: ServerOptions = {
    command: serverPath,
    args: args,
    transport: TransportKind.stdio,
    options: {
      env: { ...process.env },
    },
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: 'file', language: 'jinja' }],
    synchronize: {
      fileEvents: vscode.workspace.createFileSystemWatcher('**/*.{j2,jinja,jinja2}'),
    },
    outputChannel: outputChannel,
    traceOutputChannel: outputChannel,
  };

  client = new LanguageClient(
    'crinkle',
    'Crinkle LSP',
    serverOptions,
    clientOptions
  );

  // Start the client and capture stderr for logging
  client.start().then(() => {
    outputChannel?.appendLine('[Crinkle] LSP server started');
  }).catch((error) => {
    outputChannel?.appendLine(`[Crinkle] Failed to start LSP server: ${error}`);
    vscode.window.showErrorMessage(`Crinkle LSP failed to start: ${error.message}`);
  });

  context.subscriptions.push({
    dispose: () => {
      if (client) {
        client.stop();
      }
    },
  });
}

export function deactivate(): Thenable<void> | undefined {
  if (!client) {
    return undefined;
  }
  return client.stop();
}
