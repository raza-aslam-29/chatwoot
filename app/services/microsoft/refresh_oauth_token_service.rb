class Microsoft::RefreshOauthTokenService < BaseRefreshOauthTokenService
  private

  # Gateway mode refresh is handled by the base class via /oauth/refresh.
  # This is only used as the standalone (no-gateway) fallback.
  def build_oauth_strategy
    ::MicrosoftGraphAuth.new(nil, GlobalConfigService.load('AZURE_APP_ID', ''), GlobalConfigService.load('AZURE_APP_SECRET', ''))
  end
end
