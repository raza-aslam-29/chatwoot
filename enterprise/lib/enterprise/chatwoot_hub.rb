module Enterprise::ChatwootHub
  ENTERPRISE_BASE_URL = 'https://hub.2.channelx.au'.freeze

  def base_url
    return ENV.fetch('CHATWOOT_HUB_URL', ENTERPRISE_BASE_URL) if Rails.env.development?

    ENTERPRISE_BASE_URL
  end
end
