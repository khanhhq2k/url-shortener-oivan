# frozen_string_literal: true

# Decode path cache. Two LRU-aligned layers:
# 1. On hit, EXPIRE refreshes TTL so recently used keys stay longer (recency / hot-set).
# 2. Redis maxmemory + allkeys-lru (configure in ops — see README / SETUP) evicts cold keys under memory pressure.
class DecodeCache
  PREFIX = 'shortlink:v1:'
  TTL = 7.days.to_i

  class << self
    def read(code)
      p = pool
      return nil unless p

      p.with do |r|
        key = "#{PREFIX}#{code}"
        val = r.get(key)
        if val
          # Touch recency for time-based keys; pairs with server-side LRU eviction.
          r.expire(key, TTL)
        end
        val
      end
    rescue Redis::BaseConnectionError, Redis::BaseError => e
      Rails.logger.warn("[DecodeCache] read skipped: #{e.class}: #{e.message}")
      nil
    end

    def write(code, original_url)
      p = pool
      return unless p

      p.with { |r| r.set("#{PREFIX}#{code}", original_url, ex: TTL) }
    rescue Redis::BaseConnectionError, Redis::BaseError => e
      Rails.logger.warn("[DecodeCache] write skipped: #{e.class}: #{e.message}")
    end

    private

    def pool
      return @pool if instance_variable_defined?(:@pool)

      url = ENV['REDIS_URL']
      unless url.present?
        @pool = nil
        return @pool
      end

      size = Integer(ENV.fetch('RAILS_MAX_THREADS', 5))
      @pool = ConnectionPool.new(size: size, timeout: 2) { Redis.new(url: url) }
    rescue Redis::CannotConnectError => e
      Rails.logger.warn("[DecodeCache] Redis not connected: #{e.message}")
      @pool = nil
    end
  end
end
