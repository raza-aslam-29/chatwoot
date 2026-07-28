class Whatsapp::FacebookApiClient
  BASE_URI = 'https://graph.facebook.com'.freeze

  def initialize(access_token = nil)
    @access_token = access_token
    @api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  def exchange_code_for_token(code, waba_id = nil)
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    if gateway_url.present?
      query_params = { code: code }
      query_params[:waba_id] = waba_id if waba_id.present?
      response = HTTParty.get(
        "#{gateway_url.chomp('/')}/whatsapp_exchange_token",
        query: query_params
      )
    else
      response = HTTParty.get(
        "#{BASE_URI}/#{@api_version}/oauth/access_token",
        query: {
          client_id: GlobalConfigService.load('WHATSAPP_APP_ID', ''),
          client_secret: GlobalConfigService.load('WHATSAPP_APP_SECRET', ''),
          code: code
        }
      )
    end

    handle_response(response, 'Token exchange failed')
  end

  def fetch_phone_numbers(waba_id)
    response = HTTParty.get(
      "#{api_base_url}/#{@api_version}/#{waba_id}/phone_numbers",
      headers: request_headers,
      query: graph_credential_params
    )

    handle_response(response, 'WABA phone numbers fetch failed')
  end

  def debug_token(input_token)
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    response = if gateway_url.present?
                 HTTParty.get(
                   "#{gateway_url.chomp('/')}/whatsapp_debug_token",
                   query: { input_token: input_token }
                 )
               else
                 HTTParty.get(
                   "#{BASE_URI}/#{@api_version}/debug_token",
                   query: {
                     input_token: input_token,
                     access_token: build_app_access_token
                   }
                 )
               end

    handle_response(response, 'Token validation failed')
  end

  def register_phone_number(phone_number_id, pin)
    response = HTTParty.post(
      "#{api_base_url}/#{@api_version}/#{phone_number_id}/register",
      headers: request_headers,
      query: graph_credential_params,
      body: { messaging_product: 'whatsapp', pin: pin.to_s }.to_json
    )

    handle_response(response, 'Phone registration failed')
  end

  def phone_number_verified?(phone_number_id)
    response = HTTParty.get(
      "#{api_base_url}/#{@api_version}/#{phone_number_id}",
      headers: request_headers,
      query: graph_credential_params
    )

    data = handle_response(response, 'Phone status check failed')
    data['code_verification_status'] == 'VERIFIED'
  end

  def subscribe_waba_webhook(waba_id, callback_url, verify_token)
    # Step 1: Subscribe app to WABA first (required before override)
    # Meta requires the app to be subscribed before using override_callback_uri
    # See: https://github.com/chatwoot/chatwoot/issues/13097
    subscribe_app_to_waba(waba_id)

    # Step 2: Override callback URL for this specific WABA
    override_waba_callback(waba_id, callback_url, verify_token)
  end

  def subscribe_app_to_waba(waba_id)
    response = HTTParty.post(
      "#{api_base_url}/#{@api_version}/#{waba_id}/subscribed_apps",
      headers: request_headers,
      query: graph_credential_params
    )

    handle_response(response, 'App subscription to WABA failed')
  end

  def override_waba_callback(waba_id, callback_url, verify_token)
    response = HTTParty.post(
      "#{api_base_url}/#{@api_version}/#{waba_id}/subscribed_apps",
      headers: request_headers,
      query: graph_credential_params,
      body: {
        override_callback_uri: callback_url,
        verify_token: verify_token,
        subscribed_fields: %w[messages smb_message_echoes]
      }.to_json
    )

    handle_response(response, 'Webhook callback override failed')
  end

  def unsubscribe_waba_webhook(waba_id)
    response = HTTParty.delete(
      "#{api_base_url}/#{@api_version}/#{waba_id}/subscribed_apps",
      headers: request_headers,
      query: graph_credential_params
    )

    handle_response(response, 'Webhook unsubscription failed')
  end

  private

  def gateway_enabled?
    ENV.fetch('CHANNELX_GATEWAY_URL', '').present?
  end

  def api_base_url
    gateway_enabled? ? "#{ENV.fetch('CHANNELX_GATEWAY_URL').chomp('/')}/send/whatsapp" : BASE_URI
  end

  # When routed through the gateway, Authorization carries this tenant's own gateway
  # API key (CHANNELX_GATEWAY_API_KEY) — never the Meta access token, which must not
  # double as a gateway credential. The Meta token still reaches Meta, just as the
  # `access_token` query param instead.
  def request_headers
    auth_token = gateway_enabled? ? ENV.fetch('CHANNELX_GATEWAY_API_KEY', '') : @access_token
    {
      'Authorization' => "Bearer #{auth_token}",
      'Content-Type' => 'application/json'
    }
  end

  def graph_credential_params
    gateway_enabled? ? { access_token: @access_token } : {}
  end

  def build_app_access_token
    app_id = GlobalConfigService.load('WHATSAPP_APP_ID', '')
    app_secret = GlobalConfigService.load('WHATSAPP_APP_SECRET', '')
    "#{app_id}|#{app_secret}"
  end

  def handle_response(response, error_message)
    raise "#{error_message}: #{response.body}" unless response.success?

    response.parsed_response
  end
end
