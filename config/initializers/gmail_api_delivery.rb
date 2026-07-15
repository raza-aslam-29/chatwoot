# config/initializers/gmail_api_delivery.rb

class GmailApiDelivery
  def initialize(values = {})
    @values = values
  end

  def deliver!(mail)
    # 1. Retrieve the email address used for this delivery
    user_name = mail.smtp_envelope_from || @values[:user_name]
    channel = Channel::Email.find_by(email: user_name)
    
    if channel.blank?
      Rails.logger.error "[GMAIL_API_DELIVERY] Channel::Email not found for username: #{user_name.inspect}"
      raise "Gmail API send failed: Channel::Email not found for #{user_name}"
    end

    # 2. Get a valid, auto-refreshed OAuth access token
    access_token = Google::RefreshOauthTokenService.new(channel: channel).access_token

    # 3. Get raw MIME email content and encode it using Base64Url
    raw_content = Base64.urlsafe_encode64(mail.encoded)

    # 4. Resolve the Gmail thread ID if replying to an existing thread in Chatwoot
    parent_message_id = mail.in_reply_to
    clean_parent_message_id = parent_message_id.to_s.gsub(/^<|>$/, '')
    
    thread_id = nil
    if clean_parent_message_id.present?
      parent_msg = Message.find_by(source_id: clean_parent_message_id)
      if parent_msg
        thread_id = parent_msg.conversation.additional_attributes['gmail_thread_id']
      end
    end

    # Fallback to checking the References header if In-Reply-To did not yield a thread_id
    if thread_id.blank? && mail.references.present?
      Array.wrap(mail.references).each do |ref|
        clean_ref = ref.to_s.gsub(/^<|>$/, '')
        parent_msg = Message.find_by(source_id: clean_ref)
        if parent_msg
          thread_id = parent_msg.conversation.additional_attributes['gmail_thread_id']
          break if thread_id.present?
        end
      end
    end

    # 5. Build the API payload, including threadId if present to ensure correct threading
    body_payload = { raw: raw_content }
    body_payload[:threadId] = thread_id if thread_id.present?

    # 6. Post the payload to Gmail API's messages:send endpoint
    response = HTTParty.post(
      "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
      body: body_payload.to_json,
      headers: {
        "Authorization" => "Bearer #{access_token}",
        "Content-Type" => "application/json"
      }
    )

    unless response.code == 200
      Rails.logger.error "[GMAIL_API_DELIVERY] Send failed: #{response.code} - #{response.body}"
      
      # Extract human-readable message from Google JSON response if present
      error_message = nil
      begin
        parsed = JSON.parse(response.body)
        error_message = parsed.dig('error', 'message')
      rescue StandardError
        # Response body is not JSON
      end

      # Handle authentication failures gracefully
      if response.code == 401
        channel.authorization_error!
        error_message = "Gmail authentication failed. Please re-authorize your Google account in Inbox Settings."
      elsif response.code == 403
        error_message = "Gmail permission denied. Please verify your Google account scopes."
      end

      error_message ||= "Gmail API send failed with code #{response.code}: #{response.body.truncate(150)}"
      raise error_message
    end

    response
  end
end

ActionMailer::Base.add_delivery_method :gmail_api, GmailApiDelivery
