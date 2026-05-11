# frozen_string_literal: true

class ShortLinkParser
  class << self
    def extract_code(value)
      s = value.to_s.strip
      return nil if s.blank?

      return s if s.match?(/\A[0-9a-zA-Z]+\z/)

      uri = URI.parse(s)
      segment = uri.path.to_s.delete_prefix('/').split('/').reject(&:blank?).last
      segment.presence
    rescue URI::InvalidURIError
      nil
    end
  end
end
