class Microsoft::CallbacksController < OauthCallbackController
  include MicrosoftConcern

  private

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

  def register_with_gateway(gateway_url)
    GatewayRegistrationService.new(
      platform_type: :microsoft,
      platform_id: user_email
    ).perform
  end
end
