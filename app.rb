require 'csv'
require 'bundler'
Bundler.require

# Load custom environment variables
load 'env.rb' if File.exists?('env.rb')

module ReportConfigTester
  class App < Sinatra::Application
    enable :sessions
    set    :session_secret, "here be dragons" if File.exists?('env.rb')

    configure do
      set :root, File.dirname(__FILE__)
      set :public_folder, 'public'
    end

    def site_url
      @site_url ||= ENV.fetch('SITE', 'https://SUBDOMAIN.zipline.test')
    end

    def client(subdomain, token_method = :post)
      OAuth2::Client.new(
        ENV['OAUTH2_CLIENT_ID'],
        ENV['OAUTH2_CLIENT_SECRET'],
        :site         => site_url.sub('SUBDOMAIN', subdomain),
        :token_method => token_method,
      )
    end

    def access_token
      OAuth2::AccessToken.new(client(subdomain), session[:access_token], :refresh_token => session[:refresh_token])
    end

    def redirect_uri
      ENV['OAUTH2_CLIENT_REDIRECT_URI']
    end

    def subdomain
      ENV['SUBDOMAIN']
    end

    helpers do
      include Rack::Utils
      alias_method :h, :escape_html

      def pretty_json(json)
        JSON.pretty_generate(json)
      end

      def signed_in?
        !session[:access_token].nil?
      end

      def markdown(text)
        options  = { :autolink => true, :space_after_headers => true, :fenced_code_blocks => true }
        markdown = Redcarpet::Markdown.new(HTMLRenderer, options)
        markdown.render(text)
      end

      def markdown_readme
        markdown(File.read(File.join(File.dirname(__FILE__), "README.md")))
      end

      def site_host
        'here'
      end
    end

    get '/' do
      erb :home
    end

    get '/sign_in' do
      scope = params[:scope] || "read"
      redirect client(subdomain).auth_code.authorize_url(:redirect_uri => redirect_uri, :scope => scope)
    end

    get '/callback' do
      if params[:error]
        erb :callback_error, :layout => !request.xhr?
      else
        new_token = client(subdomain).auth_code.get_token(params[:code], :redirect_uri => redirect_uri)
        session[:access_token]  = new_token.token
        session[:refresh_token] = new_token.refresh_token

        redirect '/'
      end
    end

    get '/refresh' do
      begin
        new_token = access_token.refresh!
        session[:access_token]  = new_token.token
        session[:refresh_token] = new_token.refresh_token
        redirect '/'
      rescue OAuth2::Error => @error
        erb :error, :layout => !request.xhr?
      rescue StandardError => _error
        redirect '/'
      end
    end

    get '/sign_out' do
      session[:access_token] = nil
      redirect '/'
    end

    get '/validate' do
      <<~DOC
      <html>
          <head>
              <title>Image Upload</title>
          </head>
          <body>
              <h1>Upload Image</h1>

              <form action="/validate" method="POST" enctype="multipart/form-data">
                  <input type="file" name="file">
                  <input type="submit" value="Upload image">
              </form>
          </body>
      </html>
      DOC
    end

    post '/validate' do
      @data = CSV.parse(params[:file][:tempfile].read)

      erb :validate
    end
  end
end
