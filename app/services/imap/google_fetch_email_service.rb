class Imap::GoogleFetchEmailService < Imap::BaseFetchEmailService
  def fetch_emails
    return [] if channel.provider_config['access_token'].blank?

    access_token = Google::RefreshOauthTokenService.new(channel: channel).access_token
    return [] if access_token.blank?

    # Gmail API query to fetch messages since the last sync window (default 2 days)
    gmail_since = (Time.zone.today - (interval || 2).to_i).strftime('%Y/%m/%d')
    
    list_response = HTTParty.get(
      "https://gmail.googleapis.com/gmail/v1/users/me/messages",
      query: { q: "(in:inbox OR is:sent) after:#{gmail_since}" },
      headers: { "Authorization" => "Bearer #{access_token}" }
    )

    if list_response.code == 401
      channel.authorization_error!
      return []
    end

    return [] unless list_response.code == 200

    messages = (list_response.parsed_response['messages'] || []).reverse
    inbound_emails = []

    messages.each do |msg|
      msg_id = msg['id']
      thread_id = msg['threadId']

      # 1. Fetch metadata first to get the Message-ID header (highly optimized)
      meta_response = HTTParty.get(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/#{msg_id}",
        query: { format: 'metadata', metadataHeaders: ['Message-ID'] },
        headers: { "Authorization" => "Bearer #{access_token}" }
      )
      next unless meta_response.code == 200

      headers = meta_response.parsed_response.dig('payload', 'headers') || []
      message_id_header = headers.find { |h| h['name']&.casecmp?('message-id') }&.dig('value')
      clean_message_id = message_id_header.to_s.gsub(/^<|>$/, '')

      # Check if this email is already processed by Chatwoot
      next if clean_message_id.present? && email_already_present?(channel, clean_message_id)

      # 2. Fetch the raw RFC822 content only for new/missing emails
      raw_response = HTTParty.get(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/#{msg_id}",
        query: { format: 'raw' },
        headers: { "Authorization" => "Bearer #{access_token}" }
      )
      next unless raw_response.code == 200

      raw_content = Base64.urlsafe_decode64(raw_response.parsed_response['raw'])
      inbound_mail = build_mail_from_string(raw_content)
      if inbound_mail.present?
        inbound_mail['X-Gmail-Thread-ID'] = thread_id
        inbound_emails << inbound_mail
      end
    end

    inbound_emails
  rescue StandardError => e
    Rails.logger.error "[GMAIL_API::FETCH_EMAIL_SERVICE] Error fetching Gmail: #{e.message}"
    []
  end

  def terminate_imap_connection
    # No-op: We are using the Gmail REST API, so no IMAP client connection is created or needs to be terminated.
  end
end
