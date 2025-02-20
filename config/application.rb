require_relative 'boot'

require 'rails'
# Pick the frameworks you want:
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'active_storage/engine'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_view/railtie'
# require 'action_cable/engine'
require 'sprockets/railtie'
require 'rails/test_unit/railtie'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Kitsu
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.0

    # Enable assets (used by rails_admin, emails)
    config.assets.enabled = true
    config.assets.prefix = '/api/assets'
    config.assets.digest = true
    config.assets.export_concurrent = false

    # CSRF protection breaks some of our routes, make it opt-in
    config.action_controller.default_protect_from_forgery = false

    # UTC all the way
    config.time_zone = 'UTC'

    # Clients are in charge of localization, so we get out of the way and do our best to help them
    config.i18n.enforce_available_locales = false
    config.i18n.default_locale = :en
    config.i18n.fallbacks = true

    # Include all concern directories in app/*/concerns
    concern_dirs = Dir['app/*/concerns'].map { |d| File.expand_path(d) }
    config.eager_load_paths += concern_dirs
    # config.eager_load_paths += [Rails.root.join('lib')]
    # Rip out any non-unique entries
    config.eager_load_paths.uniq!

    # Allow autoloading any lib files
    config.autoload_paths << Rails.root.join('lib')

    # Set log level to LOG_LEVEL environment variable
    config.log_level = ENV['LOG_LEVEL'] || :info

    # Normally we wanna be API-only, but we mount some admin panels in, so... :(
    config.api_only = false

    config.ssl_options = {
      redirect: {
        exclude: -> (request) { request.path.start_with?('/api/_health') }
      }
    }

    # Set up Flipper's Memoizer middleware
    config.middleware.insert_before 0, Flipper::Middleware::Memoizer
    # Enable CORS
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins '*'
        resource '*', headers: :any,
                      methods: :any,
                      credentials: false,
                      max_age: 1.hour
      end
    end

    # Email Server
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.deliver_later_queue_name = 'soon'
    if ENV['POSTMARK_API_TOKEN']
      config.action_mailer.delivery_method = :postmark
      config.action_mailer.postmark_settings = {
        api_token: ENV['POSTMARK_API_TOKEN']
      }
    else
      config.action_mailer.delivery_method = :smtp
      config.action_mailer.smtp_settings = {
        address: ENV['SMTP_ADDRESS'],
        port: ENV['SMTP_PORT']&.to_i,
        user_name: ENV['SMTP_USERNAME'],
        password: ENV['SMTP_PASSWORD'],
        authentication: ENV['SMTP_AUTHENTICATION']&.to_sym
      }.compact
    end

    # Redis caching
    config.cache_store = :redis_cache_store, {
      driver: :hiredis,
      url: ENV['REDIS_URL'],
      expires_in: 1.day
    }

    # Set ActiveJob adapter
    config.active_job.queue_adapter = :sidekiq
    config.active_job.default_queue_name = :later

    # Configure Scaffold Generators
    config.generators do |g|
      g.authorization :policy
      g.serialization :jsonapi_resource
      g.resource_controller :resource_controller
    end
  end
end
