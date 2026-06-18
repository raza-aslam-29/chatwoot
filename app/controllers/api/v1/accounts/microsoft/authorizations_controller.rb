class Api::V1::Accounts::Microsoft::AuthorizationsController < Api::V1::Accounts::OauthAuthorizationController
  include MicrosoftConcern

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

  # Gateway mode: the gateway holds the Azure client id/secret and builds the
  # authorize URL itself. We only hand it the signed state (sgid + source_server).
  def gateway_authorize_url(gateway_url)
    state = gateway_state(gateway_url)
    return if state.blank?

    "#{gateway_url.chomp('/')}/microsoft/login?state=#{CGI.escape(state)}"
  end

  # Standalone mode (no gateway): build the authorize URL locally with own creds.
  def local_authorize_url
    microsoft_client.auth_code.authorize_url(
      {
        redirect_uri: "#{base_url}/microsoft/callback",
        scope: scope,
        prompt: 'consent',
        state: gateway_state('')
      }
    )
  end

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
