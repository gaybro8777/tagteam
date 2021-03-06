# frozen_string_literal: true

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods

  # @TODO move to a rake task
  config.before(:suite) do
    if Rails.env.test?
      begin
        DatabaseCleaner.start
      ensure
        DatabaseCleaner.clean
      end
    else
      system("bundle exec rake factory_bot:lint RAILS_ENV='test'")
    end
  end
end
