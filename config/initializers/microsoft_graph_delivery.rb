# config/initializers/microsoft_graph_delivery.rb

class MicrosoftGraphDelivery
  SEND_MAIL_URL = 'https://graph.microsoft.com/v1.0/me/sendMail'.freeze

  def initialize(values = {})
    @values = values
  end

  def deliver!(mail)
    # 1. Retrieve the email address used for this delivery
    user_name = mail.smtp_envelope_from || @values[:user_name]
    channel = Channel::Email.find_by(email: user_name)

    if channel.blank?
      Rails.logger.error "[MS_GRAPH_DELIVERY] Channel::Email not found for username: #{user_name.inspect}"
      raise "Microsoft Graph send failed: Channel::Email not found for #{user_name}"
    end

    # 2. Get a valid, auto-refreshed OAuth access token
    access_token = Microsoft::RefreshOauthTokenService.new(channel: channel).access_token

    # 3. Send the MIME message Chatwoot already built, base64-encoded. Posting raw MIME
    #    (rather than a JSON message + createReply) keeps Chatwoot's own Message-ID,
    #    In-Reply-To and References headers, which conversation matching depends on.
    response = HTTParty.post(
      SEND_MAIL_URL,
      body: Base64.strict_encode64(mail.encoded),
      headers: {
        'Authorization' => "Bearer #{access_token}",
        'Content-Type' => 'text/plain'
      }
    )

    # Graph returns 202 Accepted with an empty body on success.
    unless response.code == 202
      Rails.logger.error "[MS_GRAPH_DELIVERY] Send failed: #{response.code} - #{response.body}"

      error_message = nil
      begin
        parsed = JSON.parse(response.body)
        error_message = parsed.dig('error', 'message')
      rescue StandardError
        # Response body is not JSON
      end

      if response.code == 401
        channel.authorization_error!
        error_message = 'Outlook authentication failed. Please re-authorize your Microsoft account in Inbox Settings.'
      elsif response.code == 403
        error_message = 'Outlook permission denied. Please verify your Microsoft account scopes (Mail.Send).'
      end

      error_message ||= "Microsoft Graph send failed with code #{response.code}: #{response.body.truncate(150)}"
      raise error_message
    end

    response
  end
end

ActionMailer::Base.add_delivery_method :microsoft_graph, MicrosoftGraphDelivery
