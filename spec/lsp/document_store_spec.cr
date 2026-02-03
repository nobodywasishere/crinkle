require "../spec_helper"

describe Crinkle::LSP do
  describe Crinkle::LSP::DocumentStore do
    it "opens and retrieves documents" do
      store = Crinkle::LSP::DocumentStore.new
      store.open("file:///test.j2", "jinja2", "content", 1)

      retrieved = store.get("file:///test.j2")
      retrieved.should_not be_nil
      retrieved.try(&.text).should eq "content"
    end

    it "updates documents" do
      store = Crinkle::LSP::DocumentStore.new
      store.open("file:///test.j2", "jinja2", "old content", 1)
      store.update("file:///test.j2", "new content", 2)

      doc = store.get("file:///test.j2")
      doc.try(&.text).should eq "new content"
      doc.try(&.version).should eq 2
    end

    it "closes documents" do
      store = Crinkle::LSP::DocumentStore.new
      store.open("file:///test.j2", "jinja2", "content", 1)
      store.close("file:///test.j2")

      store.get("file:///test.j2").should be_nil
      store.open?("file:///test.j2").should be_false
    end

    it "tracks open documents" do
      store = Crinkle::LSP::DocumentStore.new
      store.open("file:///a.j2", "jinja2", "a", 1)
      store.open("file:///b.j2", "jinja2", "b", 1)

      store.size.should eq 2
      store.uris.should contain "file:///a.j2"
      store.uris.should contain "file:///b.j2"
    end

    it "applies incremental changes" do
      store = Crinkle::LSP::DocumentStore.new
      store.open("file:///test.j2", "jinja2", "Hello World", 1)

      range = Crinkle::LSP::Range.new(
        Crinkle::LSP::Position.new(0, 6),
        Crinkle::LSP::Position.new(0, 11)
      )
      store.apply_change("file:///test.j2", range, "Crystal", 2)

      doc = store.get("file:///test.j2")
      doc.try(&.text).should eq "Hello Crystal"
      doc.try(&.version).should eq 2
    end

    describe "memory management" do
      it "tracks memory usage" do
        store = Crinkle::LSP::DocumentStore.new
        store.open("file:///a.j2", "jinja2", "Hello", 1)
        store.open("file:///b.j2", "jinja2", "World", 1)

        # Memory should be at least the text size
        store.memory_usage.should be >= 10
      end

      it "evicts stale caches when limit exceeded" do
        store = Crinkle::LSP::DocumentStore.new

        # Open documents and cache diagnostics
        5.times do |i|
          doc = store.open("file:///doc#{i}.j2", "jinja2", "{{ x }}", 1)
          doc.cache_diagnostics(Array(Crinkle::LSP::Diagnostic).new)
        end

        # All should have cached diagnostics
        5.times do |i|
          store.get("file:///doc#{i}.j2").try(&.cached_lsp_diagnostics).should_not be_nil
        end

        # Evict with a small limit
        evicted = store.evict_stale_caches(2)

        evicted.should eq 3
      end

      it "evicts least recently used first" do
        store = Crinkle::LSP::DocumentStore.new

        # Open documents in order
        store.open("file:///old.j2", "jinja2", "old", 1).cache_diagnostics(Array(Crinkle::LSP::Diagnostic).new)
        store.open("file:///middle.j2", "jinja2", "middle", 1).cache_diagnostics(Array(Crinkle::LSP::Diagnostic).new)
        store.open("file:///new.j2", "jinja2", "new", 1).cache_diagnostics(Array(Crinkle::LSP::Diagnostic).new)

        # Access old document to make it recently used
        store.get("file:///old.j2")

        # Evict to keep only 1
        store.evict_stale_caches(1)

        # Old should still have cache (was accessed most recently)
        store.get("file:///old.j2").try(&.cached_lsp_diagnostics).should_not be_nil
        # Middle should have been evicted (least recently used)
        store.get("file:///middle.j2").try(&.cached_lsp_diagnostics).should be_nil
      end
    end
  end
end
