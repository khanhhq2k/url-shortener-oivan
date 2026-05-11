# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Short links API' do
  describe 'POST /encode' do
    it 'returns a shortened_link and round-trips via decode' do
      long = 'https://example.com/a/very/long/path'
      post '/encode', params: { url: long }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include('shortened_link')
      expect(body['shortened_link']).to include('/')

      post '/decode', params: { url: body['shortened_link'] }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['original_link']).to eq(long)
    end

    it 'returns the same shortened_link for the same long URL' do
      url = 'https://example.com/duplicate'
      post '/encode', params: { url: }, as: :json
      first_link = response.parsed_body['shortened_link']

      post '/encode', params: { url: }, as: :json
      expect(response.parsed_body['shortened_link']).to eq(first_link)
    end

    it 'rejects invalid URLs' do
      post '/encode', params: { url: 'ftp://files.example/resource' }, as: :json
      expect(response).to have_http_status(422)
      expect(response.parsed_body['error']).to be_present
    end

    it 'requires url parameter' do
      post '/encode', params: {}, as: :json
      expect(response).to have_http_status(422)
      expect(response.parsed_body['error']).to be_present
    end
  end

  describe 'POST /decode' do
    it 'resolves by path segment (slug only)' do
      url = 'https://site.example/page'
      post '/encode', params: { url: }, as: :json
      slug = response.parsed_body['shortened_link'].split('/').last

      post '/decode', params: { url: slug }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['original_link']).to eq(url)
    end

    it 'returns 404 for unknown code' do
      post '/decode', params: { url: 'http://localhost:3000/zzzZZZ999' }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to be_present
    end

    it 'returns 422 when no short code can be extracted' do
      post '/decode', params: { url: 'https://example.com/' }, as: :json
      expect(response).to have_http_status(422)
    end

    it 'requires url parameter' do
      post '/decode', params: {}, as: :json
      expect(response).to have_http_status(422)
    end
  end
end
