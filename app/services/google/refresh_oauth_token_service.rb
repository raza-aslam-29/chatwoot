class Google::RefreshOauthTokenService < BaseRefreshOauthTokenService
  private

  # Gateway mode refresh is handled by the base class via /oauth/refresh.
  # This is only used as the standalone (no-gateway) fallback.
  def build_oauth_strategy
    app_id = GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil)
    app_secret = GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_SECRET', nil)

    OmniAuth::Strategies::GoogleOauth2.new(nil, app_id, app_secret)
  end
end
