class Microsoft::CallbacksController < OauthCallbackController
  include MicrosoftConcern

  # In gateway mode the gateway already exchanged the code and redirects here with the
  # tokens, so skip the local exchange. Standalone mode falls back to the parent.
  def show
    return super unless gateway_mode?

    handle_response
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    redirect_to '/'
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

  def oauth_client
    microsoft_client
  end

  def provider_name
    'microsoft'
  end

  def imap_address
    'outlook.office365.com'
  end

  def find_channel_by_email
    Channel::Email.find_by(email: user_email, account: account)
  end

  def update_channel(channel_email)
    channel_email.update!({
                            imap_login: user_email, imap_address: 'outlook.office365.com',
                            imap_port: '993', imap_enabled: true,
                            provider: 'microsoft',
                            provider_config: {
                              access_token: parsed_body['access_token'],
                              refresh_token: parsed_body['refresh_token'],
                              expires_on: (Time.current.utc + 1.hour).to_s
                            }
                          })
  end

  def create_channel_with_inbox
    ActiveRecord::Base.transaction do
      channel_email = Channel::Email.create!(email: user_email, account: account)

      account.inboxes.create!(
        account: account,
        channel: channel_email,
        name: users_data['name'] || fallback_name
      )
      channel_email
    end
  end

  def users_data
    id_token = parsed_body['id_token'] || parsed_body[:id_token]
    decoded_token = JWT.decode id_token, nil, false
    decoded_token[0]
  end

  def user_email
    @user_email ||= users_data['email'].presence ||
                    users_data['preferred_username'].presence ||
                    users_data['upn'].presence
  end

  def fallback_name
    user_email.split('@').first.parameterize.titleize
  end

  def register_with_gateway(_gateway_url)
    # The gateway already stored the refresh token during /microsoft/callback. This call
    # just ensures the tenant exists and syncs the gateway api/hmac keys so Chatwoot can
    # authenticate to /oauth/refresh later.
    GatewayRegistrationService.new(
      platform_type: :microsoft,
      platform_id: user_email
    ).perform
  end
end
