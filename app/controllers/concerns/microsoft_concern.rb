module MicrosoftConcern
  extend ActiveSupport::Concern

  def microsoft_client
    app_id = GlobalConfigService.load('AZURE_APP_ID', nil)
    app_secret = GlobalConfigService.load('AZURE_APP_SECRET', nil)

    ::OAuth2::Client.new(app_id, app_secret,
                         {
                           site: 'https://login.microsoftonline.com',
                           authorize_url: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
                           token_url: 'https://login.microsoftonline.com/common/oauth2/v2.0/token'
                         })
  end

  private

  # Microsoft Graph scopes — the Outlook channel fetches and sends over Graph, not IMAP/SMTP.
  # Mail.Read (not Mail.ReadBasic) is required to read a message's raw MIME via $value.
  def scope
    'offline_access openid profile email https://graph.microsoft.com/Mail.Read ' \
      'https://graph.microsoft.com/Mail.Send https://graph.microsoft.com/User.Read'
  end
end
