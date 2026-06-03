require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

# Require the gems listed in Gemfile
Bundler.require(*Rails.groups)

module NcinoConsumerApi
  class Application < Rails::Application
    # Initialize configuration defaults for Rails 7.0
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    config.time_zone = 'UTC'
    config.active_record.default_timezone = :utc

    # Background job processing with Shoryuken
    config.active_job.queue_adapter = :shoryuken

    # API-only application
    config.api_only = true

    # Custom error classes
    config.autoload_paths << Rails.root.join('lib')

    # Logger configuration
    config.log_level = :info
    config.logger = ActiveSupport::Logger.new(STDOUT)
    config.log_formatter = ::Logger::Formatter.new
  end
end
