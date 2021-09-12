# frozen_string_literal: true

require_relative "../browser"
require "sinatra/base"

module RubyEventStore
  module Browser
    class App < Sinatra::Base
      def self.for(event_store_locator:, host: nil, path: nil, api_url: nil, environment: :production, related_streams_query: DEFAULT_RELATED_STREAMS_QUERY)
        self.tap do |app|
          app.settings.instance_exec do
            set :event_store_locator, event_store_locator
            set :related_streams_query, -> { related_streams_query }
            set :host, host
            set :root_path, path
            set :api_url, api_url
            set :environment, environment
            set :public_folder, "#{__dir__}/../../../public"
          end
        end
      end

      configure do
        set :host, nil
        set :root_path, nil
        set :api_url, nil
        set :event_store_locator, -> {}
        set :related_streams_query, nil
        set :protection, except: :path_traversal

        mime_type :json, "application/vnd.api+json"
      end

      get "/api/events/:id" do
        begin
          json Event.new(
            event_store: settings.event_store_locator,
            params: symbolized_params,
          )
        rescue RubyEventStore::EventNotFound
          404
        end
      end

      get "/api/streams/:id" do
        json GetStream.new(
          stream_name: params[:id],
          routing: routing,
          related_streams_query: settings.related_streams_query,
        )
      end

      get "/api/streams/:id/relationships/events" do
        json GetEventsFromStream.new(
          event_store: settings.event_store_locator,
          params: symbolized_params,
          routing: routing,
        )
      end

      get %r{/(events/.*|streams/.*)?} do
        erb %{
          <!DOCTYPE html>
          <html>
            <head>
              <title>RubyEventStore::Browser</title>
              <link type="text/css" rel="stylesheet" href="<%= css_src %>">
              <meta name="ruby-event-store-browser-settings" content='<%= browser_settings %>'>
            </head>
            <body>
              <script type="text/javascript" src="<%= js_src %>"></script>
            </body>
          </html>
        }
      end

      helpers do
        def symbolized_params
          params.each_with_object({}) { |(k, v), h| v.nil? ? next : h[k.to_sym] = v }
        end

        def routing
          Routing.new(
            settings.host || request.base_url,
            path
          )
        end

        def path
          settings.root_path || request.script_name
        end

        def js_src
          name = "ruby_event_store_browser.js"
          local_file_url(name) || cdn_file_url(name)
        end

        def css_src
          name = "ruby_event_store_browser.css"
          local_file_url(name) || cdn_file_url(name)
        end

        def local_file_url(name)
          File.join(path, name) if File.exist?(File.join(settings.public_folder, name))
        end

        def cdn_file_url(name)
          "https://d3iay4bmfswobf.cloudfront.net/#{commit_sha}/#{name}"
        end

        def commit_sha
          $LOAD_PATH
            .select { |x| x.end_with? "ruby_event_store-browser/lib" }
            .map    { |x| x.split("/")[-3] }
            .map    { |x| x.split("-")[-1] }
            .first
        end

        def browser_settings
          JSON.dump({
            rootUrl:    routing.root_url,
            apiUrl:     settings.api_url || routing.api_url,
            resVersion: RubyEventStore::VERSION
          })
        end

        def json(data)
          content_type :json
          JSON.dump data.as_json
        end
      end
    end
  end
end
