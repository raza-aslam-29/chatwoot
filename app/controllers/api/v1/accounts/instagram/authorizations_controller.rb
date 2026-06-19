class Api::V1::Accounts::Instagram::AuthorizationsController < Api::V1::Accounts::OauthAuthorizationController
  include InstagramConcern
  include Instagram::IntegrationHelper

  def create
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')

    redirect_url = gateway_url.present? ? gateway_authorize_url(gateway_url) : local_authorize_url

    if redirect_url
      render json: { success: true, url: redirect_url }
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  # Gateway mode: the gateway holds the Instagram app id/secret and builds the
  # Instagram authorize URL itself. We only hand it the signed state (account token
  # + source_server). No Instagram app credentials are needed on this instance.
  def gateway_authorize_url(gateway_url)
    return unless ensure_gateway_tenant!

    state = gateway_state(gateway_url)
    return if state.blank?

    "#{gateway_url.chomp('/')}/instagram/login?state=#{CGI.escape(state)}"
  end

  # Standalone mode (no gateway): build the authorize URL locally with the
  # instance's own Instagram app credentials.
  # https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login#step-1--get-authorization
  def local_authorize_url
    instagram_client.auth_code.authorize_url(
      {
        redirect_uri: "#{base_url}/instagram/callback",
        scope: REQUIRED_SCOPES.join(','),
        enable_fb_login: '0',
        force_authentication: '1',
        response_type: 'code',
        state: gateway_state('')
      }
    )
  end

  # When routing through the gateway, embed source_server and token inside the state so the
  # gateway can extract it and use it as the target for redirection — keeping redirect_uri clean.
  def gateway_state(gateway_url)
    token = generate_instagram_token(Current.account.id)
    return token if gateway_url.blank?

    source_server = params[:source_server].presence || ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    Base64.urlsafe_encode64({ token: token, source_server: source_server }.to_json, padding: false)
  end
end
