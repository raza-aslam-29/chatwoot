class Api::V1::Accounts::Google::FinalizesController < Api::V1::Accounts::BaseController
  include GoogleConcern

  def create
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    
    # Needs to strictly match the redirect URI that generated the auth code
    callback_redirect_uri = gateway_url.present? ? "#{gateway_url}/google/callback" : "#{base_url}/google/callback"

    @response = google_client.auth_code.get_token(
      params[:code],
      redirect_uri: callback_redirect_uri
    )

    inbox, already_exists = find_or_create_inbox

    # Register the inbox/tenant with the Gateway to map inbound/outbound routing
    register_with_gateway(gateway_url) if gateway_url.present?

    render json: {
      inbox_id: inbox.id,
      already_exists: already_exists
    }
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def find_or_create_inbox
    channel_email = find_channel_by_email
    channel_exists = channel_email.present?

    channel_email ||= create_channel_with_inbox
    update_channel(channel_email)

    channel_email.reauthorized!

    [channel_email.inbox, channel_exists]
  end

  def find_channel_by_email
    Channel::Email.find_by(email: users_data['email'], account: Current.account)
  end

  def update_channel(channel_email)
    channel_email.update!({
                            imap_login: users_data['email'], imap_address: 'imap.gmail.com',
                            imap_port: '993', imap_enabled: true,
                            provider: 'google',
                            provider_config: {
                              access_token: parsed_body['access_token'],
                              refresh_token: parsed_body['refresh_token'],
                              expires_on: (Time.current.utc + 1.hour).to_s
                            }
                          })
  end

  def create_channel_with_inbox
    ActiveRecord::Base.transaction do
      channel_email = Channel::Email.create!(email: users_data['email'], account: Current.account)

      Current.account.inboxes.create!(
        account: Current.account,
        channel: channel_email,
        name: users_data['name'] || fallback_name
      )
      channel_email
    end
  end

  def users_data
    decoded_token = JWT.decode parsed_body['id_token'], nil, false
    decoded_token[0]
  end

  def fallback_name
    users_data['email'].split('@').first.parameterize.titleize
  end

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end

  def parsed_body
    @parsed_body ||= @response.response.parsed
  end

  def register_with_gateway(_gateway_url)
    # Email send/receive stays on Chatwoot. We only hand the gateway the Google
    # refresh token so it can revoke it on demand (POST oauth2.googleapis.com/revoke,
    # which needs just the token — no client secret). On re-auth with no new refresh
    # token, this is nil and the gateway keeps the previously stored one.
    GatewayRegistrationService.new(
      platform_type: :google,
      platform_id: users_data['email'],
      access_token: parsed_body['refresh_token'],
      unsub_provider: 'google'
    ).perform
  end
end
