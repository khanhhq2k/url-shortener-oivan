# frozen_string_literal: true

class Link < ApplicationRecord
  MAX_URL_LENGTH = 2048

  before_validation :apply_normalized_original_url

  validates :original_url, presence: true, length: { maximum: MAX_URL_LENGTH }

  after_create :assign_slug!
  after_create_commit :warm_decode_cache

  class << self
    def normalize_url(raw)
      return if raw.blank?

      uri = URI.parse(raw.to_s.strip)
      return unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      return if uri.host.blank?

      uri = uri.normalize
      uri.scheme = uri.scheme.downcase
      uri.host = uri.host&.downcase
      uri.fragment = nil
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def encode_long_url(raw)
      normalized = normalize_url(raw)
      return [:invalid, nil] unless normalized

      link = find_by(original_url: normalized)
      return [:ok, link] if link

      begin
        [:ok, create!(original_url: normalized)]
      rescue ActiveRecord::RecordNotUnique
        [:ok, find_by!(original_url: normalized)]
      end
    end

    def find_by_short_code(code)
      find_by(slug: code)
    end

    def decode_long_url(raw)
      code = ShortLinkParser.extract_code(raw)
      return [:invalid, nil] if code.blank?

      cached = DecodeCache.read(code)
      return [:ok, cached] if cached

      link = find_by_short_code(code)
      return [:not_found, nil] unless link

      DecodeCache.write(code, link.original_url)
      [:ok, link.original_url]
    end
  end

  def short_code
    slug.presence || Base62.encode(id)
  end

  private

  def assign_slug!
    unless Link.column_names.include?('slug')
      Link.connection.schema_cache.clear!
      Link.reset_column_information
    end

    update_columns(slug: Base62.encode(id))
  end

  def apply_normalized_original_url
    return if original_url.blank?

    self.original_url = self.class.normalize_url(original_url)
  end

  def warm_decode_cache
    DecodeCache.write(short_code, original_url)
  end
end
