# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShortLinkParser do
  describe '.extract_code' do
    it 'returns nil for blank and nil' do
      expect(described_class.extract_code(nil)).to be_nil
      expect(described_class.extract_code('')).to be_nil
      expect(described_class.extract_code('   ')).to be_nil
    end

    it 'returns the raw string when it is only Base62 characters' do
      expect(described_class.extract_code('1')).to eq('1')
      expect(described_class.extract_code('aZ9')).to eq('aZ9')
    end

    it 'strips surrounding whitespace before treating as raw code' do
      expect(described_class.extract_code('  ab12  ')).to eq('ab12')
    end

    it 'takes the last non-blank path segment for full URLs' do
      expect(
        described_class.extract_code('https://short.test/abc')
      ).to eq('abc')

      expect(
        described_class.extract_code('http://localhost:3000/foo/bar')
      ).to eq('bar')
    end

    it 'handles trailing slashes by using the last segment' do
      expect(
        described_class.extract_code('https://x.example/p/tail/')
      ).to eq('tail')
    end

    it 'returns nil when the path has no segment (host-only URL)' do
      expect(described_class.extract_code('https://example.com')).to be_nil
      expect(described_class.extract_code('https://example.com/')).to be_nil
    end

    it 'returns nil on invalid URI' do
      expect(described_class.extract_code("http://exa\nmple.com/x")).to be_nil
    end
  end
end
