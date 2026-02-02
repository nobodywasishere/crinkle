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
  end

  # Diagnostic message
  struct Diagnostic
    include JSON::Serializable

    property range : Range
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

    def initialize(@text_document_sync : TextDocumentSyncOptions? = nil) : Nil
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
end
