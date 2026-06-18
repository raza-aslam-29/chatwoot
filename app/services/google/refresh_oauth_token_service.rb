class Google::RefreshOauthTokenService < BaseRefreshOauthTokenService
  # In gateway mode the Google client secret lives only on the gateway, so we refresh
  # via the gateway's /google/refresh endpoint instead of calling Google directly.
  def refresh_tokens
    return super if gateway_url.blank?

    new_tokens = refresh_via_gateway
    update_channel_provider_config(new_tokens)
    channel.reload.provider_config
  end

  private

  def gateway_url
    @gateway_url ||= ENV.fetch('CHANNELX_GATEWAY_URL', '')
  end

  def refresh_via_gateway
    refresh_token = provider_config[:refresh_token]
    body = { refresh_token: refresh_token }.to_json

    response = HTTParty.post(
      "#{gateway_url.chomp('/')}/google/refresh",
      body: body,
      headers: {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{GatewayRegistrationService.gateway_api_key}",
        'X-Channelx-Signature' => GatewayRegistrationService.sign(body)
      }
    )
    raise "Gateway Google refresh failed: #{response.code} #{response.body}" unless response.success?

    data = response.parsed_response
    {
      access_token: data['access_token'],
      refresh_token: data['refresh_token'].presence || refresh_token,
      expires_at: Time.current.utc.to_i + data['expires_in'].to_i
    }
  end

  # Standalone fallback: build the OAuth strategy locally with this instance's creds.
  def build_oauth_strategy
    app_id = GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil)
    app_secret = GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_SECRET', nil)

    OmniAuth::Strategies::GoogleOauth2.new(nil, app_id, app_secret)
  end
end
