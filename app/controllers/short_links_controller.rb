# frozen_string_literal: true

class ShortLinksController < ApplicationController
  def encode
    url_param = params.require(:url)
    status, link = Link.encode_long_url(url_param)
    case status
    when :invalid
      render json: { error: 'url must be a valid http(s) URL' }, status: :unprocessable_entity
    when :ok
      render json: { shortened_link: short_url(link) }, status: :ok
    end
  rescue ActionController::ParameterMissing
    render json: { error: 'parameter url is required' }, status: :unprocessable_entity
  end

  # POST /decode — JSON body { "url": "<short-url-or-slug>" } (same shape as /encode for a consistent API).
  def decode
    url_param = params.require(:url)
    status, original = Link.decode_long_url(url_param)
    case status
    when :invalid
      render json: { error: 'could not extract a short code from url' }, status: :unprocessable_entity
    when :not_found
      render json: { error: 'short link not found' }, status: :not_found
    when :ok
      render json: { original_link: original }, status: :ok
    end
  rescue ActionController::ParameterMissing
    render json: { error: 'parameter url is required' }, status: :unprocessable_entity
  end

  private

  def short_url(link)
    base = ENV['PUBLIC_APP_ROOT'].presence || request.base_url
    "#{base}/#{link.short_code}"
  end
end
