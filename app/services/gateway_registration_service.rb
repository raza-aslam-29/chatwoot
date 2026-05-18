class GatewayRegistrationService
  def initialize(platform_type:, platform_id:)
    @platform_type = platform_type.to_s
    @platform_id = platform_id.to_s
  end

  def perform
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    return if gateway_url.blank?

    register_uri = URI.join(gateway_url.to_s.strip.gsub(/\/?$/, '/'), 'register')
    payload = {
      platform_type: @platform_type,
      platform_id: @platform_id,
      chatwoot_url: base_url
    }

    Rails.logger.info "[GatewayRegistration] Registering #{@platform_type} (#{@platform_id}) with gateway: #{register_uri}"

    response = HTTParty.post(
      register_uri.to_s,
      body: payload.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    unless response.success?
      Rails.logger.error "[GatewayRegistration] Failed to register with gateway: #{response.code} - #{response.body}"
    end
    response
  rescue StandardError => e
    Rails.logger.error "[GatewayRegistration] Error registering with gateway: #{e.message}"
    nil
  end

  private

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end
end
