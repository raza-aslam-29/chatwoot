class Instagram::SendOnInstagramService < Instagram::BaseSendService
  private

  def channel_class
    Channel::Instagram
  end

  # Deliver a message with the given payload.
  # https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/messaging-api
  #
  # When a gateway is configured, outbound is routed THROUGH the gateway: the gateway
  # holds the token and forwards to Meta, so it is the single control point (revoke =
  # gateway refuses the send). Otherwise we call Meta directly.
  def send_message(message_content)
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    response = gateway_url.present? ? send_via_gateway(gateway_url, message_content) : send_direct(message_content)

    process_response(response, message_content)
  end

  def send_direct(message_content)
    instagram_id = channel.instagram_id.presence || 'me'
    HTTParty.post(
      "https://graph.instagram.com/v22.0/#{instagram_id}/messages",
      body: message_content,
      query: { access_token: channel.access_token }
    )
  end

  def send_via_gateway(gateway_url, message_content)
    body = message_content.to_json
    uri = "#{gateway_url.chomp('/')}/send/instagram/#{channel.instagram_id}"
    api_key = GatewayRegistrationService.api_key

    Rails.logger.info "[GatewayRegistration] Sending outbound Instagram message to Gateway: #{uri}"
    Rails.logger.info "[GatewayRegistration] Using API Key Prefix: #{api_key.to_s[0..7]}... (length: #{api_key.to_s.length})"

    response = HTTParty.post(
      uri,
      body: body,
      headers: {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{api_key}",
        'X-Channelx-Signature' => GatewayRegistrationService.sign(body)
      }
    )

    Rails.logger.info "[GatewayRegistration] Gateway response: #{response.code} — #{response.body}"
    response
  end

  def merge_human_agent_tag(params)
    global_config = GlobalConfig.get('ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT')

    return params unless global_config['ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT']

    params[:messaging_type] = 'MESSAGE_TAG'
    params[:tag] = 'HUMAN_AGENT'
    params
  end
end
