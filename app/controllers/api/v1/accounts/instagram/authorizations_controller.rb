class Api::V1::Accounts::Instagram::AuthorizationsController < Api::V1::Accounts::OauthAuthorizationController
  include InstagramConcern
  include Instagram::IntegrationHelper

  def create
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    callback_redirect_uri = gateway_url.present? ? "#{gateway_url}/instagram/callback" : "#{base_url}/instagram/callback"

    # https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login#step-1--get-authorization
    redirect_url = instagram_client.auth_code.authorize_url(
      {
        redirect_uri: callback_redirect_uri,
        scope: REQUIRED_SCOPES.join(','),
        enable_fb_login: '0',
        force_authentication: '1',
        response_type: 'code',
        state: gateway_state(gateway_url)
      }
    )
    if redirect_url
      render json: { success: true, url: redirect_url }
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  # When routing through the gateway, embed source_server and token inside the state so the
  # gateway can extract it and use it as the target for redirection — keeping redirect_uri clean.
  def gateway_state(gateway_url)
    token = generate_instagram_token(Current.account.id)
    return token if gateway_url.blank?

    source_server = params[:source_server].presence || ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    Base64.urlsafe_encode64({ token: token, source_server: source_server }.to_json, padding: false)
  end
end
