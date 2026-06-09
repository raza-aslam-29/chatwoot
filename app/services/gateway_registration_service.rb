class GatewayRegistrationService
  API_KEY_CONFIG = 'CHANNELX_GATEWAY_API_KEY'.freeze
  HMAC_KEY_CONFIG = 'CHANNELX_GATEWAY_HMAC_KEY'.freeze
  SIGNATURE_HEADER = 'X-Channelx-Signature'.freeze
  BOOTSTRAP_HEADER = 'X-Bootstrap-Token'.freeze

  def initialize(platform_type:, platform_id:)
    @platform_type = platform_type.to_s
    @platform_id = platform_id.to_s
  end

  def perform
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    return if gateway_url.blank?

    register_uri = URI.join(gateway_url.to_s.strip.gsub(%r{/?$}, '/'), 'register')
    body = {
      platform_type: @platform_type,
      platform_id: @platform_id,
      chatwoot_url: base_url
    }.to_json

    Rails.logger.info "[GatewayRegistration] Registering #{@platform_type} (#{@platform_id}) with gateway: #{register_uri}"

    response = HTTParty.post(register_uri.to_s, body: body, headers: request_headers(body))

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
end
