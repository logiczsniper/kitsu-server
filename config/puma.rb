workers Integer(ENV['WEB_CONCURRENCY'] || 4)
threads_count = Integer(ENV['RAILS_MAX_THREADS'] || 6)
threads 0, threads_count

nakayoshi_fork true
preload_app!
quiet

rackup      DefaultRackup
port        ENV['PORT'] || 3000
environment ENV['RACK_ENV'] || 'development'

on_worker_boot do
  # Worker specific setup for Rails 4.1+
  # See: https://devcenter.heroku.com/articles/deploying-rails-applications-with-the-puma-web-server#on-worker-boot
  ActiveRecord::Base.establish_connection
  ActiveRecord::Base.connection.execute("SET statement_timeout = '12s'")
end

before_fork do
  require 'puma_worker_killer'

  PumaWorkerKiller.config do |config|
    config.rolling_restart_frequency = 6.hours
    config.rolling_pre_term = ->(worker) {
      puts "Worker #{worker.inspect} being killed by rolling restart"
    }
  end
  PumaWorkerKiller.start
end

lowlevel_error_handler do |ex, env|
  Raven.capture_exception(
    ex,
    message: ex.message,
    extra: { puma: env, culprit: 'Puma' }
  )
  # note the below is just a Rack response
  [500, {}, [<<-MESSAGE.squish]]
    An unknown error has occurred. If you continue to have problems, contact help@kitsu.io\n
  MESSAGE
end
