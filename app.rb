require 'guillotine'
require 'redis'

module Katana
    class App < Guillotine::App
      # use redis adapter with redistogo
      uri = URI.parse(ENV["REDISTOGO_URL"])
      REDIS = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
      adapter = Guillotine::Adapters::RedisAdapter.new REDIS
      set :service => Guillotine::Service.new(adapter, :strip_query => false,
                                              :strip_anchor => false,
                                              :default_url => ENV["DEFAULT_URL"])

      # authenticate everything except GETs
      before do
        unless request.request_method == "GET"
          protected!
        end
      end

      get '/' do
        do_redirection
      end

      get "/*" do
        do_redirection(params[:splat].first)
      end

      if ENV['TWEETBOT_API']
        # experimental (unauthenticated) API endpoint for tweetbot
        get '/api/create/?' do
          status, head, body = settings.service.create(params[:url], params[:code])

          if loc = head['Location']
            "#{File.join("http://", request.host, loc)}"
          else
            500
          end
        end
      end

      # helper methods
      helpers do
        def do_redirection(code=nil)
          if code.nil?
            default_url = settings.service.default_url
            redirect default_url if !default_url.nil?
          else
            escaped = Addressable::URI.escape(code)
            status, head, body = settings.service.get(escaped)
            [status, head, simple_escape(body)]
          end
        end

        # Private: helper method to protect URLs with Rack Basic Auth
        #
        # Throws 401 if authorization fails
        def protected!
          return unless ENV["HTTP_USER"]
          unless authorized?
            response['WWW-Authenticate'] = %(Basic realm="Restricted Area")
            throw(:halt, [401, "Not authorized\n"])
          end
        end

        # Private: helper method to check if authorization parameters match the
        # set environment variables
        #
        # Returns true or false
        def authorized?
          @auth ||=  Rack::Auth::Basic::Request.new(request.env)
          user = ENV["HTTP_USER"]
          pass = ENV["HTTP_PASS"]
          @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == [user, pass]
        end
      end

    end
end
