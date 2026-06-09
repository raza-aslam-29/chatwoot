class OauthCallbackController < ApplicationController
  def show
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    callback_redirect_uri = gateway_url.present? ? "#{gateway_url}/#{provider_name}/callback" : "#{base_url}/#{provider_name}/callback"

    @response = oauth_client.auth_code.get_token(
      oauth_code,
      redirect_uri: callback_redirect_uri
    )

    handle_response
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    redirect_to '/'
  end

  private

  def handle_response
    inbox, already_exists = find_or_create_inbox

    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    register_with_gateway(gateway_url) if gateway_url.present?

    if already_exists
      redirect_to app_email_inbox_settings_url(account_id: account.id, inbox_id: inbox.id)
    else
      redirect_to app_email_inbox_agents_url(account_id: account.id, inbox_id: inbox.id)
    end
  end

  def find_or_create_inbox
    channel_email = find_channel_by_email
    # we need this value to know where to redirect on sucessful processing of the callback
    channel_exists = channel_email.present?

    channel_email ||= create_channel_with_inbox
    update_channel(channel_email)

    # reauthorize channel, this code path only triggers when microsoft auth is successful
    # reauthorized will also update cache keys for the associated inbox
    channel_email.reauthorized!

    [channel_email.inbox, channel_exists]
  end

  def find_channel_by_email
    Channel::Email.find_by(email: users_data['email'], account: account)
  end

  def update_channel(channel_email)
    channel_email.update!({
                            imap_login: users_data['email'], imap_address: imap_address,
                            imap_port: '993', imap_enabled: true,
                            provider: provider_name,
                            provider_config: {
                              access_token: parsed_body['access_token'],
                              refresh_token: parsed_body['refresh_token'],
                              expires_on: (Time.current.utc + 1.hour).to_s
                            }
                          })
  end

  def provider_name
    raise NotImplementedError
  end

  def register_with_gateway(gateway_url)
    # To be implemented by subclasses if needed
  end

  def oauth_client
    raise NotImplementedError
  end

  def create_channel_with_inbox
    ActiveRecord::Base.transaction do
      channel_email = Channel::Email.create!(email: users_data['email'], account: account)

      account.inboxes.create!(
        account: account,
        channel: channel_email,
        name: users_data['name'] || fallback_name
      )
      channel_email
    end
  end

  def users_data
    decoded_token = JWT.decode parsed_body[:id_token], nil, false
    decoded_token[0]
  end

  def account_from_signed_id
    raise ActionController::BadRequest, 'Missing state variable' if params[:state].blank?

    token = parsed_state_token
    account = GlobalID::Locator.locate_signed(token)
    raise 'Invalid or expired state' if account.nil?

    account
  end

  def parsed_state_token
    return nil if params[:state].blank?

    begin
      padded_state = params[:state]
      missing_padding = padded_state.length % 4
      padded_state += '=' * (4 - missing_padding) if missing_padding > 0

      decoded = JSON.parse(Base64.urlsafe_decode64(padded_state))
      decoded['sgid'] || params[:state]
    rescue StandardError
      params[:state]
    end
  end

  def account
    @account ||= account_from_signed_id
  end

  # Fallback name, for when name field is missing from users_data
  def fallback_name
    users_data['email'].split('@').first.parameterize.titleize
  end

  def oauth_code
    params[:code]
  end

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end

  def parsed_body
    @parsed_body ||= @response.response.parsed
  end
end
