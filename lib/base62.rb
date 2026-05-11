# frozen_string_literal: true

module Base62
  class Error < StandardError; end

  ALPHABET = [*'0'..'9', *'a'..'z', *'A'..'Z'].freeze
  RADIX = ALPHABET.size
  INDEX = ALPHABET.each_with_index.to_h.freeze

  module_function

  def encode(integer)
    raise Error, 'expected positive Integer' unless integer.is_a?(Integer) && integer.positive?

    n = integer
    out = +''
    while n.positive?
      n, r = n.divmod(RADIX)
      out << ALPHABET[r]
    end
    out.reverse
  end

  def decode(string)
    raise Error, 'expected non-empty String' unless string.is_a?(String) && string.present?

    value = 0
    string.each_char do |ch|
      idx = INDEX[ch]
      raise Error, "invalid Base62 character: #{ch.inspect}" unless idx

      value = (value * RADIX) + idx
    end
    raise Error, 'decoded to zero' if value.zero?

    value
  end
end
