module Crinkle::LSP
  # Configuration for Crinkle LSP semantic features
  struct Config
    include YAML::Serializable

    property version : Int32 = 1

    @[YAML::Field(key: "template_paths")]
    property template_paths : Array(String) = ["templates/"]

    property schema : SchemaConfig = SchemaConfig.new

    property inference : InferenceConfig = InferenceConfig.new

    @[YAML::Field(key: "dev_server")]
    property dev_server : DevServerConfig? = nil

    def initialize(
      @version : Int32 = 1,
      @template_paths : Array(String) = ["templates/"],
      @schema : SchemaConfig = SchemaConfig.new,
      @inference : InferenceConfig = InferenceConfig.new,
      @dev_server : DevServerConfig? = nil,
    ) : Nil
    end

    # Load config from .crinkle/config.yaml (relative to root_path)
    def self.load(root_path : String) : Config
      config_path = File.join(root_path, ".crinkle", "config.yaml")

      if File.exists?(config_path)
        Config.from_yaml(File.read(config_path))
      else
        # Return default config if not found
        Config.new
      end
    rescue
      # Return default config on parse error
      Config.new
    end
  end

  struct SchemaConfig
    include YAML::Serializable

    property path : String = ".crinkle/schema.json"
    property? watch : Bool = true

    def initialize(
      @path : String = ".crinkle/schema.json",
      @watch : Bool = true,
    ) : Nil
    end
  end

  struct InferenceConfig
    include YAML::Serializable

    property? enabled : Bool = true

    @[YAML::Field(key: "cross_template")]
    property? cross_template : Bool = true

    def initialize(
      @enabled : Bool = true,
      @cross_template : Bool = true,
    ) : Nil
    end
  end

  struct DevServerConfig
    include YAML::Serializable

    property discover : String = ".crinkle/server.lock"

    @[YAML::Field(key: "fallback_socket")]
    property fallback_socket : String = "/tmp/crinkle-dev.sock"

    def initialize(
      @discover : String = ".crinkle/server.lock",
      @fallback_socket : String = "/tmp/crinkle-dev.sock",
    ) : Nil
    end
  end
end
