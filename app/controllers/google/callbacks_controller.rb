class Google::CallbacksController < OauthCallbackController
  include GoogleConcern

  # In gateway mode the gateway already exchanged the code, so it redirects here with
  # the tokens (no code to redeem). Skip the local exchange and create the inbox from
  # the gateway-provided tokens. Standalone mode falls back to the parent (local exchange).
  def show
    return super unless gateway_mode?

    handle_response
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    redirect_to '/'
  end

  def find_channel_by_email
    # find by imap_login first, and then by email
    # this ensures the legacy users can migrate correctly even if inbox email address doesn't match
    imap_channel = Channel::Email.find_by(imap_login: users_data['email'], account: account)
    return imap_channel if imap_channel

    Channel::Email.find_by(email: users_data['email'], account: account)
  end

  private

  def gateway_mode?
    ENV.fetch('CHANNELX_GATEWAY_URL', '').present?
  end

  # Gateway mode: tokens arrive as query params instead of being exchanged locally.
  def parsed_body
    return super unless gateway_mode?

    @parsed_body ||= {
      access_token: params[:access_token],
      refresh_token: params[:refresh_token],
      id_token: params[:id_token],
      expires_in: params[:expires_in]
    }.with_indifferent_access
  end

  def provider_name
    'google'
  end

  def imap_address
    'imap.gmail.com'
  end

  def oauth_client
    # from GoogleConcern (only used in standalone mode)
    google_client
  end

  def register_with_gateway(_gateway_url)
    # Email send/receive stays on Chatwoot. Hand the gateway the refresh token so it
    # can refresh the access token (gateway holds the client secret) and revoke on demand.
    GatewayRegistrationService.new(
      platform_type: :google,
      platform_id: users_data['email'],
      access_token: parsed_body[:refresh_token],
      unsub_provider: 'google'
    ).perform
  end
end
