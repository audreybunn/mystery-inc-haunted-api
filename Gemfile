source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.2.0'

# Rails framework
gem 'rails', '~> 7.0.8'

# Database
gem 'mysql2', '~> 0.5'

# Background job processing with SQS
gem 'shoryuken', '~> 6.0'

# Redis for caching and locking
gem 'redis', '~> 5.0'
gem 'redis-namespace', '~> 1.10'

# Distributed locking
gem 'redlock', '~> 1.3'

# HTTP client
gem 'httparty', '~> 0.21'

# Configuration management
gem 'dotenv-rails', '~> 2.8'

# JSON handling
gem 'oj', '~> 3.16'

group :development, :test do
  gem 'pry-rails'
  gem 'rspec-rails', '~> 6.0'
  gem 'factory_bot_rails', '~> 6.2'
  gem 'faker', '~> 3.2'
end

group :test do
  gem 'shoulda-matchers', '~> 5.3'
  gem 'webmock', '~> 3.18'
  gem 'database_cleaner-active_record', '~> 2.1'
end
