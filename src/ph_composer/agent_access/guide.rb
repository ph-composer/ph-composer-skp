# frozen_string_literal: true

require "digest"

module PhComposer
  module AgentAccess
    # The operating guide an agent reads through the connection itself (context/AGENT_INTERFACE.md,
    # "Discover before acting"): `guide.md` beside this file is docs/AGENT_GUIDE.md as written, copied by
    # `make fixtures` and compared by the offline suite, so the guide has one source. It is read once at
    # load and frozen, so the listener's workers can name it without touching anything else.
    #
    # Each second-level section is a topic, and each third-level section is its own topic under it, so
    # one topic fits a reply however the guide grows. The text before the first section is `overview`.
    # It is documentation, never Model data: nothing a Model holds reaches it.
    module Guide
      PATH = File.join(__dir__, "guide.md")
      TEXT = File.read(PATH, :encoding => "UTF-8").freeze
      DIGEST = Digest::SHA256.hexdigest(TEXT).freeze

      module_function

      def slug(title)
        title.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      end

      # [{id, title, text}] in the guide's order. A heading inside a fenced block is text.
      def split(text)
        topics = [{ "id" => "overview", "title" => "Overview", "lines" => [] }]
        parent = nil
        fenced = false
        text.each_line do |line|
          fenced = !fenced if line.start_with?("```")
          if fenced || line.start_with?("```")
            topics.last.fetch("lines") << line
          elsif (heading = line[/\A## (.+)/, 1])
            parent = slug(heading)
            topics << { "id" => parent, "title" => heading.strip, "lines" => [line] }
          elsif (heading = line[/\A### (.+)/, 1]) && parent
            topics << { "id" => "#{parent}.#{slug(heading)}", "title" => heading.strip, "lines" => [line] }
          else
            topics.last.fetch("lines") << line
          end
        end
        topics.map do |topic|
          { "id" => topic.fetch("id"), "title" => topic.fetch("title"),
            "text" => topic.fetch("lines").join.strip + "\n" }
        end
      end

      TOPICS = DeepCopy.frozen(split(TEXT))

      # Which guide this build carries: it changes with the API and with its own text.
      def version
        { "api" => "#{API::MAJOR}.#{API::MINOR}", "extension" => VERSION, "digest" => DIGEST }
      end

      def index
        { "version" => version, "topics" => TOPICS.map do |topic|
          { "id" => topic.fetch("id"), "title" => topic.fetch("title"), "bytes" => topic.fetch("text").bytesize }
        end }
      end

      def topic(id)
        found = TOPICS.find { |topic| topic.fetch("id") == id }
        unless found
          raise CodedError.new("params.invalid", "There is no guide topic #{id.to_s[0, 80].inspect}; discover " \
                                                 "with section guide lists them.")
        end

        { "version" => version }.merge(found)
      end
    end
  end
end
