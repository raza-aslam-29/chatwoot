class Api::V1::Accounts::Microsoft::FinalizesController < Api::V1::Accounts::BaseController
  include MicrosoftConcern

  def create
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    
    # Needs to strictly match the redirect URI that generated the auth code
    callback_redirect_uri = gateway_url.present? ? "#{gateway_url}/microsoft/callback" : "#{base_url}/microsoft/callback"

    @response = microsoft_client.auth_code.get_token(
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
    raise 'Microsoft id_token did not contain an email/UPN — cannot create inbox' if user_email.blank?

    channel_email = find_channel_by_email
    channel_exists = channel_email.present?

    channel_email ||= create_channel_with_inbox
    update_channel(channel_email)

    channel_email.reauthorized!

    [channel_email.inbox, channel_exists]
  end

  def find_channel_by_email
    Channel::Email.find_by(email: user_email, account: Current.account)
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
      channel_email = Channel::Email.create!(email: user_email, account: Current.account)

      Current.account.inboxes.create!(
        account: Current.account,
        channel: channel_email,
        name: users_data['name'] || fallback_name
      )
      channel_email
    end
  end

  def users_data
    # Supports both string and symbol keys if parsed differently
    id_token = parsed_body['id_token'] || parsed_body[:id_token]
    decoded_token = JWT.decode id_token, nil, false
    decoded_token[0]
  end

  # Microsoft id_tokens don't always include the `email` claim — work/school (Azure AD)
  # accounts usually carry the address in `preferred_username` or `upn` instead.
  def user_email
    @user_email ||= users_data['email'].presence ||
                    users_data['preferred_username'].presence ||
                    users_data['upn'].presence
  end

  def fallback_name
    user_email.split('@').first.parameterize.titleize
  end

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end

  def parsed_body
    @parsed_body ||= @response.response.parsed
  end

  def register_with_gateway(gateway_url)
    GatewayRegistrationService.new(
      platform_type: :microsoft,
      platform_id: user_email
    ).perform
  end
end
