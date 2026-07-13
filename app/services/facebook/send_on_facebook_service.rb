class Facebook::SendOnFacebookService < Base::SendOnChannelService
  private

  def channel_class
    Channel::FacebookPage
  end

  def perform_reply
    send_message_to_facebook fb_text_message_params if message.content.present?

    if message.attachments.present?
      message.attachments.each do |attachment|
        send_message_to_facebook fb_attachment_message_params(attachment)
      end
    end
  rescue Facebook::Messenger::FacebookError => e
    # TODO : handle specific errors or else page will get disconnected
    handle_facebook_error(e)
    Messages::StatusUpdateService.new(message, 'failed', e.message).perform
  end

  def send_message_to_facebook(delivery_params)
    parsed_result = deliver_message(delivery_params)
    return if parsed_result.nil?

    if parsed_result['error'].present?
      Messages::StatusUpdateService.new(message, 'failed', external_error(parsed_result)).perform
      Rails.logger.info "Facebook::SendOnFacebookService: Error sending message to Facebook : Page - #{channel.page_id} : #{parsed_result}"
    end

    message.update!(source_id: parsed_result['message_id']) if parsed_result['message_id'].present?
  end

  def deliver_message(delivery_params)
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    return deliver_via_gateway(gateway_url, delivery_params) if gateway_url.present?

    result = Facebook::Messenger::Bot.deliver(delivery_params, page_id: channel.page_id)
    JSON.parse(result)
  rescue JSON::ParserError
    Messages::StatusUpdateService.new(message, 'failed', 'Facebook was unable to process this request').perform
    Rails.logger.error "Facebook::SendOnFacebookService: Error parsing JSON response from Facebook : Page - #{channel.page_id} : #{result}"
    nil
  rescue Net::OpenTimeout
    Messages::StatusUpdateService.new(message, 'failed', 'Request timed out, please try again later').perform
    Rails.logger.error "Facebook::SendOnFacebookService: Timeout error sending message to Facebook : Page - #{channel.page_id}"
    nil
  end

  # Route outbound through the gateway: it holds the page token and forwards to Meta,
  # so it is the single control point (revoke = gateway refuses the send). The page
  # token never lives on this instance. Mirrors Instagram::SendOnInstagramService.
  def deliver_via_gateway(gateway_url, delivery_params)
    body = delivery_params.to_json
    uri = "#{gateway_url.chomp('/')}/send/facebook/#{channel.page_id}"
    api_key = GatewayRegistrationService.api_key

    Rails.logger.info "[GatewayRegistration] Sending outbound Facebook message to Gateway: #{uri}"
    Rails.logger.info "[GatewayRegistration] Using API Key Prefix: #{api_key.to_s[0..7]}... (length: #{api_key.to_s.length})"

    response = HTTParty.post(
      uri,
      body: body,
      headers: {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{api_key}",
        'X-Channelx-Signature' => GatewayRegistrationService.sign(body)
      }
    )

    Rails.logger.info "[GatewayRegistration] Gateway response: #{response.code} — #{response.body}"
    JSON.parse(response.body)
  rescue JSON::ParserError
    Messages::StatusUpdateService.new(message, 'failed', 'Facebook was unable to process this request').perform
    Rails.logger.error "Facebook::SendOnFacebookService: Error parsing gateway response : Page - #{channel.page_id} : #{response&.body}"
    nil
  end

  def fb_text_message_params
    {
      recipient: { id: contact.get_source_id(inbox.id) },
      message: fb_text_message_payload,
      **messaging_options
    }
  end

  def fb_text_message_payload
    if message.content_type == 'input_select' && message.content_attributes['items'].any?
      {
        text: message.content,
        quick_replies: message.content_attributes['items'].map do |item|
          {
            content_type: 'text',
            payload: item['title'],
            title: item['title']
          }
        end
      }
    else
      { text: message.outgoing_content }
    end
  end

  def external_error(response)
    # https://developers.facebook.com/docs/graph-api/guides/error-handling/
    error_message = response['error']['message']
    error_code = response['error']['code']

    "#{error_code} - #{error_message}"
  end

  def fb_attachment_message_params(attachment)
    {
      recipient: { id: contact.get_source_id(inbox.id) },
      message: {
        attachment: {
          type: attachment_type(attachment),
          payload: {
            url: attachment.download_url
          }
        }
      },
      **messaging_options
    }
  end

  # Meta deprecated the ACCOUNT_UPDATE/CONFIRMED_EVENT_UPDATE/POST_PURCHASE_UPDATE
  # message tags (rejected with error 100 / subcode 1893061). Agent replies happen
  # inside the 24-hour standard messaging window, so send them as RESPONSE with no
  # tag. Only when the Human Agent feature is enabled do we use the still-valid
  # HUMAN_AGENT tag, which extends the window to 7 days.
  def messaging_options
    if GlobalConfigService.load('ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT', nil)
      { messaging_type: 'MESSAGE_TAG', tag: 'HUMAN_AGENT' }
    else
      { messaging_type: 'RESPONSE' }
    end
  end

  def attachment_type(attachment)
    return attachment.file_type if %w[image audio video file].include? attachment.file_type

    'file'
  end

  def sent_first_outgoing_message_after_24_hours?
    # we can send max 1 message after 24 hour window
    conversation.messages.outgoing.where('id > ?', conversation.last_incoming_message.id).count == 1
  end

  def handle_facebook_error(exception)
    # Refer: https://github.com/jgorset/facebook-messenger/blob/64fe1f5cef4c1e3fca295b205037f64dfebdbcab/lib/facebook/messenger/error.rb
    return unless exception.to_s.include?('The session has been invalidated') || exception.to_s.include?('Error validating access token')

    channel.authorization_error!
  end
end
