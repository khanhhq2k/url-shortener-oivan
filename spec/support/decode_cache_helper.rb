# frozen_string_literal: true

module DecodeCacheHelper
  def reset_decode_cache!
    return unless DecodeCache.instance_variable_defined?(:@pool)

    DecodeCache.remove_instance_variable(:@pool)
  end

  def with_redis_env(url)
    previous = ENV['REDIS_URL']
    if url
      ENV['REDIS_URL'] = url
    else
      ENV.delete('REDIS_URL')
    end
    reset_decode_cache!
    yield
  ensure
    if previous
      ENV['REDIS_URL'] = previous
    else
      ENV.delete('REDIS_URL')
    end
    reset_decode_cache!
  end
end

RSpec.configure do |config|
  config.include DecodeCacheHelper
end
