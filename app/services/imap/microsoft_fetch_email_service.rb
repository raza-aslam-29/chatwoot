class Imap::MicrosoftFetchEmailService < Imap::BaseFetchEmailService
  GRAPH_BASE = 'https://graph.microsoft.com/v1.0'.freeze

  # Mirrors the Gmail service's inbox+sent coverage. Graph's /me/messages spans the whole
  # mailbox (including Deleted Items and Clutter), so folders are scoped explicitly.
  FOLDERS = %w[inbox sentitems].freeze

  # Graph defaults to 10 messages per page; the docs warn that large pages with full
  # payloads can hit a gateway timeout, so we keep $select narrow and the page modest.
  PAGE_SIZE = 50
  MAX_PAGES = 20

  def fetch_emails
    return [] if channel.provider_config['access_token'].blank?

    access_token = Microsoft::RefreshOauthTokenService.new(channel: channel).access_token
    return [] if access_token.blank?

    FOLDERS.flat_map { |folder| fetch_folder(folder, access_token) }
  rescue StandardError => e
    Rails.logger.error "[MS_GRAPH::FETCH_EMAIL_SERVICE] Error fetching Outlook mail: #{e.message}"
    []
  end

  def terminate_imap_connection
    # No-op: we use the Microsoft Graph REST API, so no IMAP client connection exists.
  end

  private

  def fetch_folder(folder, access_token)
    inbound_emails = []
    url = list_url(folder)
    pages = 0

    while url.present? && pages < MAX_PAGES
      response = graph_get(url, access_token)

      if response.code == 401
        channel.authorization_error!
        return inbound_emails
      end
      break unless response.code == 200

      body = response.parsed_response
      (body['value'] || []).each do |msg|
        inbound_mail = build_inbound_mail(msg, access_token)
        inbound_emails << inbound_mail if inbound_mail.present?
      end

      # Follow @odata.nextLink verbatim — it already carries the original query params.
      url = body['@odata.nextLink']
      pages += 1
    end

    inbound_emails
  end

  # $orderby properties must also appear in $filter, in the same order, ahead of any
  # filter-only properties — otherwise Graph returns InefficientFilter.
  # Encoded with ERB::Util.url_encode (%20 for spaces) rather than to_query, whose
  # form-encoding turns spaces into '+' inside the OData expressions.
  def list_url(folder)
    query = {
      '$select' => 'id,internetMessageId,conversationId,receivedDateTime',
      '$filter' => "receivedDateTime ge #{graph_since}",
      '$orderby' => 'receivedDateTime asc',
      '$top' => PAGE_SIZE
    }.map { |key, value| "#{key}=#{ERB::Util.url_encode(value.to_s)}" }.join('&')

    "#{GRAPH_BASE}/me/mailFolders/#{folder}/messages?#{query}"
  end

  def build_inbound_mail(msg, access_token)
    clean_message_id = msg['internetMessageId'].to_s.gsub(/^<|>$/, '')
    return if clean_message_id.present? && email_already_present?(channel, clean_message_id)

    raw_content = fetch_raw_mime(msg['id'], access_token)
    return if raw_content.blank?

    inbound_mail = build_mail_from_string(raw_content)
    return if inbound_mail.blank?

    # Outlook's conversationId is the threading equivalent of Gmail's threadId.
    inbound_mail['X-MS-Thread-ID'] = msg['conversationId'] if msg['conversationId'].present?
    inbound_mail
  end

  # $value returns the RFC822 MIME as text/plain, not JSON.
  def fetch_raw_mime(message_id, access_token)
    response = graph_get("#{GRAPH_BASE}/me/messages/#{CGI.escape(message_id)}/$value", access_token)
    return unless response.code == 200

    response.body
  end

  def graph_get(url, access_token)
    HTTParty.get(url, headers: { 'Authorization' => "Bearer #{access_token}" })
  end

  def graph_since
    (Time.zone.today - (interval || 2).to_i).strftime('%Y-%m-%dT00:00:00Z')
  end
end
