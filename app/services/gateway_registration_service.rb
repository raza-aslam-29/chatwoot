# Handles all Chatwoot-to-Gateway communication using a single static API key.
#
# Authentication flow:
#   * Every request to the gateway carries `Authorization: Bearer <key>`.
#   * The key is stored in the customer's Chatwoot .env as `CHANNELX_GATEWAY_API_KEY`.
#   * No registration phase, no handshake, no write to `installation_configs`.
#
# Verification of incoming webhook signatures:
#   * Incoming webhooks from the gateway are signed with the same key.
#   * verified via `GatewayRegistrationService.verify(body, signature)`.
class GatewayRegistrationService
  API_KEY_ENV      = 'CHANNELX_GATEWAY_API_KEY'.freeze
  SIGNATURE_HEADER = 'X-Channelx-Signature'.freeze

  def initialize(platform_type: nil, platform_id: nil, access_token: nil, unsub_provider: nil, token_expires_at: nil)
    @platform_type    = platform_type.to_s
    @platform_id      = platform_id.to_s
    @access_token     = access_token
    @unsub_provider   = unsub_provider
    @token_expires_at = token_expires_at
  end

  # Registers a channel (inbox) with the gateway.
  def perform
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    return if gateway_url.blank?

    api_key = ENV.fetch(API_KEY_ENV, '')
    if api_key.blank?
      Rails.logger.error '[GatewayRegistration] CHANNELX_GATEWAY_API_KEY is not set — cannot register channel'
      return
    end

    register_uri = URI.join(gateway_url.to_s.strip.gsub(%r{/?$}, '/'), 'register')
    body = {
      platform_type:    @platform_type,
      platform_id:      @platform_id,
      chatwoot_url:     base_url,
      access_token:     @access_token,
      unsub_provider:   @unsub_provider,
      token_expires_at: @token_expires_at
    }.compact.to_json

    Rails.logger.info "[GatewayRegistration] Registering #{@platform_type} (#{@platform_id}) → #{register_uri}"
    response = HTTParty.post(register_uri.to_s, body: body, headers: authorization_headers(api_key))

    unless response.success?
      Rails.logger.error "[GatewayRegistration] Channel registration failed: #{response.code} — #{response.body}"
    end

    response
  rescue StandardError => e
    Rails.logger.error "[GatewayRegistration] Error registering channel: #{e.message}"
    nil
  end

  # Removes a channel's route from the gateway. Called when an inbox is deleted.
  def unregister
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    return if gateway_url.blank? || @platform_id.blank?

    api_key = ENV.fetch(API_KEY_ENV, '')
    if api_key.blank?
      Rails.logger.error '[GatewayRegistration] CHANNELX_GATEWAY_API_KEY is not set — cannot unregister channel'
      return
    end

    register_uri = URI.join(gateway_url.to_s.strip.gsub(%r{/?$}, '/'), 'register')
    body = {
      platform_type: @platform_type,
      platform_id:   @platform_id,
      chatwoot_url:  base_url
    }.compact.to_json

    Rails.logger.info "[GatewayRegistration] Unregistering #{@platform_type} (#{@platform_id}) from gateway"
    HTTParty.delete(register_uri.to_s, body: body, headers: authorization_headers(api_key))
  rescue StandardError => e
    Rails.logger.error "[GatewayRegistration] Error unregistering from gateway: #{e.message}"
    nil
  end

  class << self
    # Return true if the environment has a static key configured.
    def registered?
      api_key.present?
    end

    # Legacy compatibility: always returns true if the key is present in env.
    def ensure_tenant_registered!
      if api_key.blank?
        Rails.logger.error '[GatewayRegistration] CHANNELX_GATEWAY_API_KEY is not set'
        return false
      end
      true
    end

    def api_key
      ENV.fetch(API_KEY_ENV, nil)
    end

    def gateway_api_key
      api_key
    end


    # Signs a request body with the static key using SHA-256 (used for outgoing Meta signature fallback check).
    def sign(body)
      key = api_key
      return nil if key.blank?

      "sha256=#{OpenSSL::HMAC.hexdigest('sha256', key, body.to_s)}"
    end

    # Constant-time verification of an incoming signature.
    def verify(body, signature)
      key = api_key
      return false if key.blank? || signature.blank?

      ActiveSupport::SecurityUtils.secure_compare(sign(body).to_s, signature.to_s)
    end
  end

  private

  def authorization_headers(api_key)
    {
      'Content-Type'  => 'application/json',
      'Authorization' => "Bearer #{api_key}"
    }
  end

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end
end
