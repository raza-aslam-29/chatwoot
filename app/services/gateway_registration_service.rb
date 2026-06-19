class GatewayRegistrationService
  API_KEY_CONFIG = 'CHANNELX_GATEWAY_API_KEY'.freeze
  HMAC_KEY_CONFIG = 'CHANNELX_GATEWAY_HMAC_KEY'.freeze
  SIGNATURE_HEADER = 'X-Channelx-Signature'.freeze
  BOOTSTRAP_HEADER = 'X-Bootstrap-Token'.freeze

  def initialize(platform_type:, platform_id:, access_token: nil, unsub_provider: nil, token_expires_at: nil)
    @platform_type = platform_type.to_s
    @platform_id = platform_id.to_s
    # Optional: the token + provider the gateway needs to revoke / send for this
    # channel (page token for Facebook, IG-login token for Instagram).
    @access_token = access_token
    @unsub_provider = unsub_provider
    # ISO8601 expiry so the gateway can refresh the Instagram token before it lapses.
    @token_expires_at = token_expires_at
  end

  def perform
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    return if gateway_url.blank?

    register_uri = URI.join(gateway_url.to_s.strip.gsub(%r{/?$}, '/'), 'register')
    body = {
      platform_type: @platform_type,
      platform_id: @platform_id,
      chatwoot_url: base_url,
      access_token: @access_token,
      unsub_provider: @unsub_provider,
      token_expires_at: @token_expires_at
    }.compact.to_json

    Rails.logger.info "[GatewayRegistration] Registering #{@platform_type} (#{@platform_id}) with gateway: #{register_uri}"

    response = HTTParty.post(register_uri.to_s, body: body, headers: request_headers(body))

    # If the gateway rejects the stored API key (e.g. gateway DB was reset), clear keys and retry with bootstrap token
    if response.code == 401 && self.class.gateway_api_key.present?
      Rails.logger.warn '[GatewayRegistration] Gateway returned 401 Unauthorized. Clearing keys and retrying...'
      clear_keys!
      response = HTTParty.post(register_uri.to_s, body: body, headers: request_headers(body))
    end

    if response.success?
      persist_keys_from_response(response)
    else
      Rails.logger.error "[GatewayRegistration] Failed to register with gateway: #{response.code} - #{response.body}"
    end

    response
  rescue StandardError => e
    Rails.logger.error "[GatewayRegistration] Error registering with gateway: #{e.message}"
    nil
  end

  # Removes this platform_id's route from the gateway (called when an inbox/channel is
  # deleted). Authenticated the same way as registration. Matched by tenant + identifier.
  def unregister
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    return if gateway_url.blank? || @platform_id.blank?

    register_uri = URI.join(gateway_url.to_s.strip.gsub(%r{/?$}, '/'), 'register')
    body = {
      platform_type: @platform_type,
      platform_id: @platform_id,
      chatwoot_url: base_url
    }.compact.to_json

    Rails.logger.info "[GatewayRegistration] Unregistering #{@platform_type} (#{@platform_id}) from gateway: #{register_uri}"
    HTTParty.delete(register_uri.to_s, body: body, headers: request_headers(body))
  rescue StandardError => e
    Rails.logger.error "[GatewayRegistration] Error unregistering from gateway: #{e.message}"
    nil
  end

  class << self
    def gateway_api_key
      GlobalConfigService.load(API_KEY_CONFIG, nil)
    end

    def hmac_key
      GlobalConfigService.load(HMAC_KEY_CONFIG, nil)
    end

    def sign(body)
      key = hmac_key
      return nil if key.blank?

      "sha256=#{OpenSSL::HMAC.hexdigest('sha256', key, body.to_s)}"
    end

    def verify(body, signature)
      key = hmac_key
      return false if key.blank? || signature.blank?

      expected = sign(body)
      ActiveSupport::SecurityUtils.secure_compare(expected.to_s, signature.to_s)
    end
  end

  private

  def request_headers(body)
    headers = { 'Content-Type' => 'application/json' }

    if self.class.gateway_api_key.present? && self.class.hmac_key.present?
      headers['Authorization'] = "Bearer #{self.class.gateway_api_key}"
      headers[SIGNATURE_HEADER] = self.class.sign(body)
    else
      bootstrap = ENV.fetch('CHANNELX_GATEWAY_BOOTSTRAP_TOKEN', '')
      headers[BOOTSTRAP_HEADER] = bootstrap if bootstrap.present?
    end

    headers
  end

  def persist_keys_from_response(response)
    parsed = response.parsed_response
    return unless parsed.is_a?(Hash)

    api_key = parsed['gateway_api_key']
    hmac = parsed['hmac_key']
    return if api_key.blank? || hmac.blank?

    upsert_config(API_KEY_CONFIG, api_key)
    upsert_config(HMAC_KEY_CONFIG, hmac)

    Rails.logger.info '[GatewayRegistration] Stored gateway credentials in installation config'
  end

  def upsert_config(name, value)
    config = InstallationConfig.find_or_initialize_by(name: name)
    config.value = value
    config.locked = true
    config.save!
  end

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end

  def clear_keys!
    InstallationConfig.find_by(name: API_KEY_CONFIG)&.destroy
    InstallationConfig.find_by(name: HMAC_KEY_CONFIG)&.destroy
    GlobalConfig.clear_cache
  end
end
