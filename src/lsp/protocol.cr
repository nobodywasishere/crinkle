require "json"

module Crinkle::LSP
  # JSON-RPC 2.0 message types

  # Base message structure with jsonrpc version
  module Message
    macro included
      include JSON::Serializable
      property jsonrpc : String = "2.0"
    end
  end

  # Request message - has id and method
  class RequestMessage
    include Message

    property id : Int64 | String
    property method : String
    property params : JSON::Any?

    def initialize(
      @id : Int64 | String,
      @method : String,
      @params : JSON::Any? = nil,
    ) : Nil
    end
  end

  # Response message - has id and either result or error
  class ResponseMessage
    include Message

    property id : (Int64 | String)?
    property result : JSON::Any?
    property error : ResponseError?

    def initialize(
      @id : (Int64 | String)?,
      @result : JSON::Any? = nil,
      @error : ResponseError? = nil,
    ) : Nil
    end
  end

  # Notification message - no id, has method
  class NotificationMessage
    include Message

    property method : String
    property params : JSON::Any?

    def initialize(@method : String, @params : JSON::Any? = nil) : Nil
    end
  end

  # Response error
  class ResponseError
    include JSON::Serializable

    property code : Int32
    property message : String
    property data : JSON::Any?

    def initialize(@code : Int32, @message : String, @data : JSON::Any? = nil) : Nil
    end
  end

  # Standard error codes
  module ErrorCodes
    ParseError           = -32700
    InvalidRequest       = -32600
    MethodNotFound       = -32601
    InvalidParams        = -32602
    InternalError        = -32603
    ServerNotInitialized = -32002
    UnknownErrorCode     = -32001
    RequestCancelled     = -32800
    ContentModified      = -32801
  end

  # Position in a text document (0-based line and character)
  struct Position
    include JSON::Serializable

    property line : Int32
    property character : Int32

    def initialize(@line : Int32, @character : Int32) : Nil
    end
  end

  # Range in a text document
  struct Range
    include JSON::Serializable

    property start : Position
    @[JSON::Field(key: "end")]
    property end_pos : Position

    def initialize(@start : Position, @end_pos : Position) : Nil
    end
  end

  # Location in a document (URI + range)
  struct Location
    include JSON::Serializable

    property uri : String
    property range : Range

    def initialize(@uri : String, @range : Range) : Nil
    end
  end

  # Text document identifier
  struct TextDocumentIdentifier
    include JSON::Serializable

    property uri : String

    def initialize(@uri : String) : Nil
    end
  end

  # Versioned text document identifier
  struct VersionedTextDocumentIdentifier
    include JSON::Serializable

    property uri : String
    property version : Int32

    def initialize(@uri : String, @version : Int32) : Nil
    end
  end

  # Text document item (full document content)
  struct TextDocumentItem
    include JSON::Serializable

    property uri : String
    @[JSON::Field(key: "languageId")]
    property language_id : String
    property version : Int32
    property text : String

    def initialize(
      @uri : String,
      @language_id : String,
      @version : Int32,
      @text : String,
    ) : Nil
    end
  end

  # Diagnostic severity
  enum DiagnosticSeverity
    Error       = 1
    Warning     = 2
    Information = 3
    Hint        = 4

    def to_json(json : JSON::Builder) : Nil
      json.number(value)
    end
  end

  # Diagnostic message
  struct Diagnostic
    include JSON::Serializable

    property range : Range
    @[JSON::Field(converter: Enum::ValueConverter(Crinkle::LSP::DiagnosticSeverity))]
    property severity : DiagnosticSeverity?
    property code : (String | Int32)?
    property source : String?
    property message : String

    def initialize(
      @range : Range,
      @message : String,
      @severity : DiagnosticSeverity? = nil,
      @code : (String | Int32)? = nil,
      @source : String? = nil,
    ) : Nil
    end
  end

  # Initialize request params
  struct InitializeParams
    include JSON::Serializable

    @[JSON::Field(key: "processId")]
    property process_id : Int32?
    @[JSON::Field(key: "rootUri")]
    property root_uri : String?
    property capabilities : ClientCapabilities
    property trace : String?

    def initialize(
      @process_id : Int32? = nil,
      @root_uri : String? = nil,
      @capabilities : ClientCapabilities = ClientCapabilities.new,
      @trace : String? = nil,
    ) : Nil
    end
  end

  # Client capabilities (minimal for now)
  struct ClientCapabilities
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentClientCapabilities?

    def initialize(@text_document : TextDocumentClientCapabilities? = nil) : Nil
    end
  end

  struct TextDocumentClientCapabilities
    include JSON::Serializable

    property synchronization : TextDocumentSyncClientCapabilities?

    def initialize(@synchronization : TextDocumentSyncClientCapabilities? = nil) : Nil
    end
  end

  struct TextDocumentSyncClientCapabilities
    include JSON::Serializable

    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool?
    @[JSON::Field(key: "willSave")]
    property will_save : Bool?
    @[JSON::Field(key: "willSaveWaitUntil")]
    property will_save_wait_until : Bool?
    @[JSON::Field(key: "didSave")]
    property did_save : Bool?

    def initialize(
      @dynamic_registration : Bool? = nil,
      @will_save : Bool? = nil,
      @will_save_wait_until : Bool? = nil,
      @did_save : Bool? = nil,
    ) : Nil
    end
  end

  # Server capabilities
  struct ServerCapabilities
    include JSON::Serializable

    @[JSON::Field(key: "textDocumentSync")]
    property text_document_sync : TextDocumentSyncOptions?
    @[JSON::Field(key: "documentFormattingProvider")]
    property document_formatting_provider : Bool?
    @[JSON::Field(key: "completionProvider")]
    property completion_provider : CompletionOptions?
    @[JSON::Field(key: "hoverProvider")]
    property hover_provider : Bool?
    @[JSON::Field(key: "signatureHelpProvider")]
    property signature_help_provider : SignatureHelpOptions?
    @[JSON::Field(key: "definitionProvider")]
    property definition_provider : Bool?
    @[JSON::Field(key: "referencesProvider")]
    property references_provider : Bool?
    @[JSON::Field(key: "documentSymbolProvider")]
    property document_symbol_provider : Bool?
    @[JSON::Field(key: "foldingRangeProvider")]
    property folding_range_provider : Bool?
    @[JSON::Field(key: "documentHighlightProvider")]
    property document_highlight_provider : Bool?
    @[JSON::Field(key: "documentLinkProvider")]
    property document_link_provider : Bool?
    @[JSON::Field(key: "workspaceSymbolProvider")]
    property workspace_symbol_provider : Bool?
    @[JSON::Field(key: "renameProvider")]
    property rename_provider : RenameOptions?
    @[JSON::Field(key: "codeActionProvider")]
    property code_action_provider : Bool?
    @[JSON::Field(key: "inlayHintProvider")]
    property inlay_hint_provider : Bool?
    property workspace : WorkspaceServerCapabilities?

    def initialize(
      @text_document_sync : TextDocumentSyncOptions? = nil,
      @document_formatting_provider : Bool? = nil,
      @completion_provider : CompletionOptions? = nil,
      @hover_provider : Bool? = nil,
      @signature_help_provider : SignatureHelpOptions? = nil,
      @definition_provider : Bool? = nil,
      @references_provider : Bool? = nil,
      @document_symbol_provider : Bool? = nil,
      @folding_range_provider : Bool? = nil,
      @document_highlight_provider : Bool? = nil,
      @document_link_provider : Bool? = nil,
      @workspace_symbol_provider : Bool? = nil,
      @rename_provider : RenameOptions? = nil,
      @code_action_provider : Bool? = nil,
      @inlay_hint_provider : Bool? = nil,
      @workspace : WorkspaceServerCapabilities? = nil,
    ) : Nil
    end
  end

  # Rename options
  struct RenameOptions
    include JSON::Serializable

    @[JSON::Field(key: "prepareProvider")]
    property? prepare_provider : Bool?

    def initialize(@prepare_provider : Bool? = nil) : Nil
    end
  end

  # Completion options
  struct CompletionOptions
    include JSON::Serializable

    @[JSON::Field(key: "triggerCharacters")]
    property trigger_characters : Array(String)?

    def initialize(@trigger_characters : Array(String)? = nil) : Nil
    end
  end

  # Signature help options
  struct SignatureHelpOptions
    include JSON::Serializable

    @[JSON::Field(key: "triggerCharacters")]
    property trigger_characters : Array(String)?

    def initialize(@trigger_characters : Array(String)? = nil) : Nil
    end
  end

  # Text document sync options
  struct TextDocumentSyncOptions
    include JSON::Serializable

    @[JSON::Field(key: "openClose")]
    property open_close : Bool?
    property change : Int32? # 0 = None, 1 = Full, 2 = Incremental
    property save : SaveOptions?

    def initialize(
      @open_close : Bool? = nil,
      @change : Int32? = nil,
      @save : SaveOptions? = nil,
    ) : Nil
    end
  end

  struct SaveOptions
    include JSON::Serializable

    @[JSON::Field(key: "includeText")]
    property include_text : Bool?

    def initialize(@include_text : Bool? = nil) : Nil
    end
  end

  # Initialize result
  struct InitializeResult
    include JSON::Serializable

    property capabilities : ServerCapabilities
    @[JSON::Field(key: "serverInfo")]
    property server_info : ServerInfo?

    def initialize(
      @capabilities : ServerCapabilities,
      @server_info : ServerInfo? = nil,
    ) : Nil
    end
  end

  struct ServerInfo
    include JSON::Serializable

    property name : String
    property version : String?

    def initialize(@name : String, @version : String? = nil) : Nil
    end
  end

  # DidOpenTextDocument params
  struct DidOpenTextDocumentParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentItem

    def initialize(@text_document : TextDocumentItem) : Nil
    end
  end

  # DidChangeTextDocument params
  struct DidChangeTextDocumentParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : VersionedTextDocumentIdentifier
    @[JSON::Field(key: "contentChanges")]
    property content_changes : Array(TextDocumentContentChangeEvent)

    def initialize(
      @text_document : VersionedTextDocumentIdentifier,
      @content_changes : Array(TextDocumentContentChangeEvent),
    ) : Nil
    end
  end

  # Content change event (full sync = just text, incremental = range + text)
  struct TextDocumentContentChangeEvent
    include JSON::Serializable

    property range : Range?
    @[JSON::Field(key: "rangeLength")]
    property range_length : Int32?
    property text : String

    def initialize(
      @text : String,
      @range : Range? = nil,
      @range_length : Int32? = nil,
    ) : Nil
    end
  end

  # DidCloseTextDocument params
  struct DidCloseTextDocumentParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier

    def initialize(@text_document : TextDocumentIdentifier) : Nil
    end
  end

  # PublishDiagnostics params
  struct PublishDiagnosticsParams
    include JSON::Serializable

    property uri : String
    property version : Int32?
    property diagnostics : Array(Diagnostic)

    def initialize(
      @uri : String,
      @diagnostics : Array(Diagnostic),
      @version : Int32? = nil,
    ) : Nil
    end
  end

  # Message type for window/logMessage and window/showMessage
  # LSP requires these as integers, not strings
  enum MessageType
    Error   = 1
    Warning = 2
    Info    = 3
    Log     = 4 # Debug level

    def to_json(json : JSON::Builder) : Nil
      json.number(value)
    end
  end

  # LogMessage params (window/logMessage notification)
  struct LogMessageParams
    include JSON::Serializable

    property type : MessageType
    property message : String

    def initialize(@type : MessageType, @message : String) : Nil
    end
  end

  # Text edit returned by formatting
  struct TextEdit
    include JSON::Serializable

    property range : Range
    @[JSON::Field(key: "newText")]
    property new_text : String

    def initialize(@range : Range, @new_text : String) : Nil
    end
  end

  # Formatting options
  struct FormattingOptions
    include JSON::Serializable

    @[JSON::Field(key: "tabSize")]
    property tab_size : Int32
    @[JSON::Field(key: "insertSpaces")]
    property? insert_spaces : Bool

    def initialize(@tab_size : Int32 = 2, @insert_spaces : Bool = true) : Nil
    end
  end

  # DocumentFormatting params
  struct DocumentFormattingParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier
    property options : FormattingOptions

    def initialize(
      @text_document : TextDocumentIdentifier,
      @options : FormattingOptions,
    ) : Nil
    end
  end

  # Completion item kind
  enum CompletionItemKind
    Text          =  1
    Method        =  2
    Function      =  3
    Constructor   =  4
    Field         =  5
    Variable      =  6
    Class         =  7
    Interface     =  8
    Module        =  9
    Property      = 10
    Unit          = 11
    Value         = 12
    Enum          = 13
    Keyword       = 14
    Snippet       = 15
    Color         = 16
    File          = 17
    Reference     = 18
    Folder        = 19
    EnumMember    = 20
    Constant      = 21
    Struct        = 22
    Event         = 23
    Operator      = 24
    TypeParameter = 25

    def to_json(json : JSON::Builder) : Nil
      json.number(value)
    end
  end

  # Completion item
  struct CompletionItem
    include JSON::Serializable

    property label : String
    property kind : CompletionItemKind?
    property detail : String?
    property documentation : String?
    @[JSON::Field(key: "sortText")]
    property sort_text : String?
    @[JSON::Field(key: "filterText")]
    property filter_text : String?
    @[JSON::Field(key: "insertText")]
    property insert_text : String?

    def initialize(
      @label : String,
      @kind : CompletionItemKind? = nil,
      @detail : String? = nil,
      @documentation : String? = nil,
      @sort_text : String? = nil,
      @filter_text : String? = nil,
      @insert_text : String? = nil,
    ) : Nil
    end
  end

  # Completion params
  struct CompletionParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier
    property position : Position

    def initialize(@text_document : TextDocumentIdentifier, @position : Position) : Nil
    end
  end

  # Hover params
  struct HoverParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier
    property position : Position

    def initialize(@text_document : TextDocumentIdentifier, @position : Position) : Nil
    end
  end

  # Reference context options (from LSP spec)
  struct ReferenceContextOptions
    include JSON::Serializable

    @[JSON::Field(key: "includeDeclaration")]
    getter? include_declaration : Bool

    def initialize(@include_declaration : Bool = true) : Nil
    end
  end

  # textDocument/references params
  struct ReferenceParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier
    property position : Position
    property context : ReferenceContextOptions?

    def initialize(
      @text_document : TextDocumentIdentifier,
      @position : Position,
      @context : ReferenceContextOptions? = nil,
    ) : Nil
    end
  end

  # Markup content for hover/completion documentation
  struct MarkupContent
    include JSON::Serializable

    property kind : String # "plaintext" | "markdown"
    property value : String

    def initialize(@kind : String, @value : String) : Nil
    end
  end

  # Hover result
  struct Hover
    include JSON::Serializable

    property contents : MarkupContent
    property range : Range?

    def initialize(@contents : MarkupContent, @range : Range? = nil) : Nil
    end
  end

  # Signature help params
  struct SignatureHelpParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier
    property position : Position

    def initialize(@text_document : TextDocumentIdentifier, @position : Position) : Nil
    end
  end

  # Parameter information for signature help
  struct ParameterInformation
    include JSON::Serializable

    property label : String
    property documentation : String?

    def initialize(@label : String, @documentation : String? = nil) : Nil
    end
  end

  # Signature information
  struct SignatureInformation
    include JSON::Serializable

    property label : String
    property documentation : String?
    property parameters : Array(ParameterInformation)?

    def initialize(
      @label : String,
      @documentation : String? = nil,
      @parameters : Array(ParameterInformation)? = nil,
    ) : Nil
    end
  end

  # Signature help result
  struct SignatureHelp
    include JSON::Serializable

    property signatures : Array(SignatureInformation)
    @[JSON::Field(key: "activeSignature")]
    property active_signature : Int32?
    @[JSON::Field(key: "activeParameter")]
    property active_parameter : Int32?

    def initialize(
      @signatures : Array(SignatureInformation),
      @active_signature : Int32? = nil,
      @active_parameter : Int32? = nil,
    ) : Nil
    end
  end

  # File change type for workspace/didChangeWatchedFiles
  enum FileChangeType
    Created = 1
    Changed = 2
    Deleted = 3

    def to_json(json : JSON::Builder) : Nil
      json.number(value)
    end
  end

  # File event for workspace/didChangeWatchedFiles
  struct FileEvent
    include JSON::Serializable

    property uri : String
    @[JSON::Field(converter: Enum::ValueConverter(FileChangeType))]
    property type : FileChangeType

    def initialize(@uri : String, @type : FileChangeType) : Nil
    end
  end

  # DidChangeWatchedFiles params
  struct DidChangeWatchedFilesParams
    include JSON::Serializable

    property changes : Array(FileEvent)

    def initialize(@changes : Array(FileEvent)) : Nil
    end
  end

  # Symbol kind for document symbols
  enum SymbolKind
    File          =  1
    Module        =  2
    Namespace     =  3
    Package       =  4
    Class         =  5
    Method        =  6
    Property      =  7
    Field         =  8
    Constructor   =  9
    Enum          = 10
    Interface     = 11
    Function      = 12
    Variable      = 13
    Constant      = 14
    String        = 15
    Number        = 16
    Boolean       = 17
    Array         = 18
    Object        = 19
    Key           = 20
    Null          = 21
    EnumMember    = 22
    Struct        = 23
    Event         = 24
    Operator      = 25
    TypeParameter = 26

    def to_json(json : JSON::Builder) : Nil
      json.number(value)
    end
  end

  # Document symbol (hierarchical)
  struct DocumentSymbol
    include JSON::Serializable

    property name : String
    property kind : SymbolKind
    property range : Range
    @[JSON::Field(key: "selectionRange")]
    property selection_range : Range
    property detail : String?
    property children : Array(DocumentSymbol)?

    def initialize(
      @name : String,
      @kind : SymbolKind,
      @range : Range,
      @selection_range : Range,
      @detail : String? = nil,
      @children : Array(DocumentSymbol)? = nil,
    ) : Nil
    end
  end

  # Document symbol params
  struct DocumentSymbolParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier

    def initialize(@text_document : TextDocumentIdentifier) : Nil
    end
  end

  # Folding range kind
  enum FoldingRangeKind
    Comment
    Imports
    Region

    def to_json(json : JSON::Builder) : Nil
      json.string(to_s.downcase)
    end
  end

  # Folding range
  struct FoldingRange
    include JSON::Serializable

    @[JSON::Field(key: "startLine")]
    property start_line : Int32
    @[JSON::Field(key: "startCharacter")]
    property start_character : Int32?
    @[JSON::Field(key: "endLine")]
    property end_line : Int32
    @[JSON::Field(key: "endCharacter")]
    property end_character : Int32?
    property kind : FoldingRangeKind?

    def initialize(
      @start_line : Int32,
      @end_line : Int32,
      @start_character : Int32? = nil,
      @end_character : Int32? = nil,
      @kind : FoldingRangeKind? = nil,
    ) : Nil
    end
  end

  # Folding range params
  struct FoldingRangeParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier

    def initialize(@text_document : TextDocumentIdentifier) : Nil
    end
  end

  # Workspace capabilities for server
  struct WorkspaceServerCapabilities
    include JSON::Serializable

    @[JSON::Field(key: "workspaceFolders")]
    property workspace_folders : WorkspaceFoldersServerCapabilities?

    def initialize(@workspace_folders : WorkspaceFoldersServerCapabilities? = nil) : Nil
    end
  end

  struct WorkspaceFoldersServerCapabilities
    include JSON::Serializable

    property? supported : Bool?
    @[JSON::Field(key: "changeNotifications")]
    property change_notifications : (Bool | String)?

    def initialize(
      @supported : Bool? = nil,
      @change_notifications : (Bool | String)? = nil,
    ) : Nil
    end
  end

  # Configuration item for workspace/configuration request
  struct ConfigurationItem
    include JSON::Serializable

    @[JSON::Field(key: "scopeUri")]
    property scope_uri : String?
    property section : String?

    def initialize(@scope_uri : String? = nil, @section : String? = nil) : Nil
    end
  end

  # Params for workspace/configuration request
  struct ConfigurationParams
    include JSON::Serializable

    property items : Array(ConfigurationItem)

    def initialize(@items : Array(ConfigurationItem)) : Nil
    end
  end

  # DidChangeConfiguration notification params
  struct DidChangeConfigurationParams
    include JSON::Serializable

    property settings : JSON::Any

    def initialize(@settings : JSON::Any) : Nil
    end
  end

  # Crinkle LSP settings (from client/editor configuration)
  struct CrinkleLspSettings
    include JSON::Serializable

    # Enable/disable linting
    @[JSON::Field(key: "lintEnabled")]
    property? lint_enabled : Bool = true

    # Maximum file size in bytes for full analysis (larger files get basic analysis)
    @[JSON::Field(key: "maxFileSize")]
    property max_file_size : Int32 = 1_000_000

    # Enable/disable diagnostics debouncing
    @[JSON::Field(key: "debounceMs")]
    property debounce_ms : Int32 = 150

    # Enable/disable property typo detection
    @[JSON::Field(key: "typoDetection")]
    property? typo_detection : Bool = true

    # Enable/disable inlay hints
    @[JSON::Field(key: "inlayHints")]
    property? inlay_hints_enabled : Bool = true

    def initialize(
      @lint_enabled : Bool = true,
      @max_file_size : Int32 = 1_000_000,
      @debounce_ms : Int32 = 150,
      @typo_detection : Bool = true,
      @inlay_hints_enabled : Bool = true,
    ) : Nil
    end
  end

  # Document highlight kind
  enum DocumentHighlightKind
    Text  = 1
    Read  = 2
    Write = 3

    def to_json(json : JSON::Builder) : Nil
      json.number(value)
    end
  end

  # Document highlight
  struct DocumentHighlight
    include JSON::Serializable

    property range : Range
    property kind : DocumentHighlightKind?

    def initialize(@range : Range, @kind : DocumentHighlightKind? = nil) : Nil
    end
  end

  # Document highlight params
  struct DocumentHighlightParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier
    property position : Position

    def initialize(@text_document : TextDocumentIdentifier, @position : Position) : Nil
    end
  end

  # Document link
  struct DocumentLink
    include JSON::Serializable

    property range : Range
    property target : String?
    property tooltip : String?

    def initialize(@range : Range, @target : String? = nil, @tooltip : String? = nil) : Nil
    end
  end

  # Document link params
  struct DocumentLinkParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier

    def initialize(@text_document : TextDocumentIdentifier) : Nil
    end
  end

  # Workspace symbol params
  struct WorkspaceSymbolParams
    include JSON::Serializable

    property query : String

    def initialize(@query : String) : Nil
    end
  end

  # Symbol information (flat, for workspace symbols)
  struct SymbolInformation
    include JSON::Serializable

    property name : String
    property kind : SymbolKind
    property location : Location
    @[JSON::Field(key: "containerName")]
    property container_name : String?

    def initialize(
      @name : String,
      @kind : SymbolKind,
      @location : Location,
      @container_name : String? = nil,
    ) : Nil
    end
  end

  # Rename params
  struct RenameParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier
    property position : Position
    @[JSON::Field(key: "newName")]
    property new_name : String

    def initialize(
      @text_document : TextDocumentIdentifier,
      @position : Position,
      @new_name : String,
    ) : Nil
    end
  end

  # Prepare rename params (same as TextDocumentPositionParams)
  struct PrepareRenameParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier
    property position : Position

    def initialize(@text_document : TextDocumentIdentifier, @position : Position) : Nil
    end
  end

  # Prepare rename result
  struct PrepareRenameResult
    include JSON::Serializable

    property range : Range
    property placeholder : String

    def initialize(@range : Range, @placeholder : String) : Nil
    end
  end

  # Workspace edit (for rename)
  struct WorkspaceEdit
    include JSON::Serializable

    property changes : Hash(String, Array(TextEdit))?

    def initialize(@changes : Hash(String, Array(TextEdit))? = nil) : Nil
    end
  end

  # Code action kind
  module CodeActionKind
    QuickFix       = "quickfix"
    Refactor       = "refactor"
    Source         = "source"
    SourceOrganize = "source.organizeImports"
  end

  # Code action params
  struct CodeActionParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier
    property range : Range
    property context : CodeActionContext

    def initialize(
      @text_document : TextDocumentIdentifier,
      @range : Range,
      @context : CodeActionContext,
    ) : Nil
    end
  end

  # Code action context
  struct CodeActionContext
    include JSON::Serializable

    property diagnostics : Array(Diagnostic)
    property only : Array(String)?

    def initialize(@diagnostics : Array(Diagnostic), @only : Array(String)? = nil) : Nil
    end
  end

  # Code action
  struct CodeAction
    include JSON::Serializable

    property title : String
    property kind : String?
    property diagnostics : Array(Diagnostic)?
    property edit : WorkspaceEdit?

    def initialize(
      @title : String,
      @kind : String? = nil,
      @diagnostics : Array(Diagnostic)? = nil,
      @edit : WorkspaceEdit? = nil,
    ) : Nil
    end
  end

  # Inlay hint kind
  enum InlayHintKind
    Type      = 1
    Parameter = 2

    def to_json(json : JSON::Builder) : Nil
      json.number(value)
    end
  end

  # Inlay hint params
  struct InlayHintParams
    include JSON::Serializable

    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier
    property range : Range

    def initialize(@text_document : TextDocumentIdentifier, @range : Range) : Nil
    end
  end

  # Inlay hint
  struct InlayHint
    include JSON::Serializable

    property position : Position
    property label : String
    property kind : InlayHintKind?
    @[JSON::Field(key: "paddingLeft")]
    property? padding_left : Bool?
    @[JSON::Field(key: "paddingRight")]
    property? padding_right : Bool?

    def initialize(
      @position : Position,
      @label : String,
      @kind : InlayHintKind? = nil,
      @padding_left : Bool? = nil,
      @padding_right : Bool? = nil,
    ) : Nil
    end
  end
end
