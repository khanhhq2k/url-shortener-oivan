# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DecodeCache do
  describe '.read / .write' do
    it 'returns nil and skips write when REDIS_URL is not set' do
      with_redis_env(nil) do
        expect(described_class.read('any')).to be_nil
        expect { described_class.write('any', 'https://example.com') }.not_to raise_error
      end
    end

    it 'reads through the pool with the prefixed key and refreshes TTL on hit (LRU-friendly)' do
      pool = instance_double(ConnectionPool)
      redis = instance_double(Redis)
      key = "#{described_class::PREFIX}myCode"
      allow(ConnectionPool).to receive(:new).and_return(pool)
      allow(pool).to receive(:with).and_yield(redis)
      allow(redis).to receive(:get).with(key).and_return('https://stored.example/path')
      expect(redis).to receive(:expire).with(key, described_class::TTL)

      with_redis_env('redis://localhost:6379/0') do
        expect(described_class.read('myCode')).to eq('https://stored.example/path')
      end
    end

    it 'does not call EXPIRE on cache miss' do
      pool = instance_double(ConnectionPool)
      redis = instance_double(Redis)
      allow(ConnectionPool).to receive(:new).and_return(pool)
      allow(pool).to receive(:with).and_yield(redis)
      allow(redis).to receive(:get).and_return(nil)
      expect(redis).not_to receive(:expire)

      with_redis_env('redis://localhost:6379/0') do
        expect(described_class.read('missing')).to be_nil
      end
    end

    it 'writes with TTL and prefixed key' do
      pool = instance_double(ConnectionPool)
      redis = instance_double(Redis)
      allow(ConnectionPool).to receive(:new).and_return(pool)
      allow(pool).to receive(:with).and_yield(redis)
      expect(redis).to receive(:set).with(
        "#{described_class::PREFIX}xyz",
        'https://original.example',
        ex: described_class::TTL
      )

      with_redis_env('redis://localhost:6379/0') do
        described_class.write('xyz', 'https://original.example')
      end
    end

    it 'returns nil and logs when read raises a Redis error' do
      pool = instance_double(ConnectionPool)
      redis = instance_double(Redis)
      allow(ConnectionPool).to receive(:new).and_return(pool)
      allow(pool).to receive(:with).and_yield(redis)
      allow(redis).to receive(:get).and_raise(Redis::CannotConnectError)

      with_redis_env('redis://localhost:6379/0') do
        allow(Rails.logger).to receive(:warn)
        expect(described_class.read('k')).to be_nil
        expect(Rails.logger).to have_received(:warn).with(/DecodeCache.*read skipped/)
      end
    end

    it 'swallows Redis errors on write' do
      pool = instance_double(ConnectionPool)
      redis = instance_double(Redis)
      allow(ConnectionPool).to receive(:new).and_return(pool)
      allow(pool).to receive(:with).and_yield(redis)
      allow(redis).to receive(:set).and_raise(Redis::TimeoutError)

      with_redis_env('redis://localhost:6379/0') do
        allow(Rails.logger).to receive(:warn)
        expect { described_class.write('a', 'https://b') }.not_to raise_error
        expect(Rails.logger).to have_received(:warn).with(/DecodeCache.*write skipped/)
      end
    end

    it 'memoizes a nil pool when Redis cannot connect at pool build time' do
      allow(ConnectionPool).to receive(:new).and_raise(Redis::CannotConnectError)
      allow(Rails.logger).to receive(:warn)

      with_redis_env('redis://no-such-host:6379/0') do
        expect(described_class.read('x')).to be_nil
        expect(Rails.logger).to have_received(:warn).with(/Redis not connected/)
      end
    end
  end
end
