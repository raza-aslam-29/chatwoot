class Api::V1::Accounts::Google::AuthorizationsController < Api::V1::Accounts::OauthAuthorizationController
  include GoogleConcern

  def create
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')

    # Static redirect_uri — must match exactly what is registered in Google Cloud Console.
    # source_server is passed via state (not as a redirect_uri query param) to avoid URI mismatch.
    callback_redirect_uri = gateway_url.present? ? "#{gateway_url}/google/callback" : "#{base_url}/google/callback"

    redirect_url = google_client.auth_code.authorize_url(
      {
        redirect_uri: callback_redirect_uri,
        scope: scope,
        response_type: 'code',
        prompt: 'consent',
        access_type: 'offline',
        state: gateway_state(gateway_url),
        client_id: GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil)
      }
    )

    if redirect_url
      render json: { success: true, url: redirect_url }
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  # When routing through the gateway, embed source_server inside the state so the
  # gateway can extract it and use it as the postMessage target — keeping redirect_uri clean.
  def gateway_state(gateway_url)
    sgid = Current.account.to_sgid(expires_in: 15.minutes).to_s
    return sgid if gateway_url.blank?

    # Use the browser origin sent by the frontend (window.location.origin) — NOT FRONTEND_URL.
    # FRONTEND_URL is often 0.0.0.0 (a bind address) which doesn't match the browser's actual origin.
    source_server = params[:source_server].presence || ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    Base64.urlsafe_encode64({ sgid: sgid, source_server: source_server }.to_json, padding: false)
  end
end
