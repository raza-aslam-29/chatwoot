class Whatsapp::Providers::WhatsappCloudService < Whatsapp::Providers::BaseService
  def send_message(phone_number, message)
    @message = message

    if message.attachments.present?
      send_attachment_message(phone_number, message)
    elsif message.content_type == 'input_select'
      send_interactive_text_message(phone_number, message)
    else
      send_text_message(phone_number, message)
    end
  end

  def send_template(phone_number, template_info, message)
    template_body = template_body_parameters(template_info)

    request_body = {
      messaging_product: 'whatsapp',
      recipient_type: 'individual', # Only individual messages supported (not group messages)
      to: phone_number,
      type: 'template',
      template: template_body
    }

    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      query: graph_credential_params,
      body: request_body.to_json
    )

    process_response(response, message)
  end

  def sync_templates
    # ensuring that channels with wrong provider config wouldn't keep trying to sync templates
    whatsapp_channel.mark_message_templates_updated
    templates = fetch_whatsapp_templates("#{business_account_path}/message_templates?access_token=#{whatsapp_channel.provider_config['api_key']}")
    whatsapp_channel.update(message_templates: templates, message_templates_last_updated: Time.now.utc) if templates.present?
  end

  # `url` is either our own gateway-routed request (first page) or a graph.facebook.com
  # pagination URL Meta handed back directly (subsequent pages) — only the former needs
  # the gateway's tenant credential; the latter already carries a working access_token.
  def fetch_whatsapp_templates(url)
    response = HTTParty.get(url, headers: request_headers_for(url))
    return [] unless response.success?

    next_url = next_url(response)

    return response['data'] + fetch_whatsapp_templates(next_url) if next_url.present?

    response['data']
  end

  def next_url(response)
    response['paging'] ? response['paging']['next'] : ''
  end

  def validate_provider_config?
    url = "#{business_account_path}/message_templates?access_token=#{whatsapp_channel.provider_config['api_key']}"
    response = HTTParty.get(url, headers: request_headers_for(url))
    response.success?
  end

  # When routed through the gateway, Authorization must carry this tenant's own gateway
  # API key (CHANNELX_GATEWAY_API_KEY) — never the Meta access token, which is not a
  # valid gateway credential. The Meta token still reaches Meta via the access_token
  # query param (see graph_credential_params).
  def api_headers
    auth_token = gateway_enabled? ? ENV.fetch('CHANNELX_GATEWAY_API_KEY', '') : whatsapp_channel.provider_config['api_key']
    { 'Authorization' => "Bearer #{auth_token}", 'Content-Type' => 'application/json' }
  end

  def gateway_enabled?
    ENV.fetch('CHANNELX_GATEWAY_URL', '').present?
  end

  def graph_credential_params
    gateway_enabled? ? { access_token: whatsapp_channel.provider_config['api_key'] } : {}
  end

  def request_headers_for(url)
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    return {} unless gateway_url.present? && url.start_with?(gateway_url)

    { 'Authorization' => "Bearer #{ENV.fetch('CHANNELX_GATEWAY_API_KEY', '')}" }
  end

  def create_csat_template(template_config)
    csat_template_service.create_template(template_config)
  end

  def delete_csat_template(template_name = nil)
    template_name ||= CsatTemplateNameService.csat_template_name(whatsapp_channel.inbox.id)
    csat_template_service.delete_template(template_name)
  end

  def get_template_status(template_name)
    csat_template_service.get_template_status(template_name)
  end

  def media_url(media_id)
    if gateway_enabled?
      "#{api_base_path}/v13.0/#{media_id}?access_token=#{whatsapp_channel.provider_config['api_key']}"
    else
      "#{api_base_path}/v13.0/#{media_id}"
    end
  end

  private

  def csat_template_service
    @csat_template_service ||= Whatsapp::CsatTemplateService.new(whatsapp_channel)
  end

  def api_base_path
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    if gateway_url.present?
      "#{gateway_url.chomp('/')}/send/whatsapp"
    else
      ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    end
  end

  # TODO: See if we can unify the API versions and for both paths and make it consistent with out facebook app API versions
  def phone_id_path
    "#{api_base_path}/v13.0/#{whatsapp_channel.provider_config['phone_number_id']}"
  end

  def business_account_path
    "#{api_base_path}/v14.0/#{whatsapp_channel.provider_config['business_account_id']}"
  end

  def send_text_message(phone_number, message)
    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      query: graph_credential_params,
      body: {
        messaging_product: 'whatsapp',
        context: whatsapp_reply_context(message),
        to: phone_number,
        text: { body: message.outgoing_content },
        type: 'text'
      }.to_json
    )

    process_response(response, message)
  end

  def send_attachment_message(phone_number, message)
    attachment = message.attachments.first
    type = %w[image audio video].include?(attachment.file_type) ? attachment.file_type : 'document'
    type_content = {
      'link': attachment.download_url
    }
    type_content['caption'] = message.outgoing_content unless %w[audio sticker].include?(type)
    type_content['filename'] = attachment.file.filename if type == 'document'
    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      query: graph_credential_params,
      body: {
        :messaging_product => 'whatsapp',
        :context => whatsapp_reply_context(message),
        'to' => phone_number,
        'type' => type,
        type.to_s => type_content
      }.to_json
    )

    process_response(response, message)
  end

  def error_message(response)
    # https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/#sample-response
    # Gateway-level failures (auth rejected, channel revoked, ...) come back as
    # `{"detail": "..."}` instead of Meta's `{"error": {"message": ...}}` shape.
    response.parsed_response&.dig('error', 'message') || response.parsed_response&.dig('detail')
  end

  def template_body_parameters(template_info)
    template_body = {
      name: template_info[:name],
      language: {
        policy: 'deterministic',
        code: template_info[:lang_code]
      }
    }

    # Enhanced template parameters structure
    # Note: Legacy format support (simple parameter arrays) has been removed
    # in favor of the enhanced component-based structure that supports
    # headers, buttons, and authentication templates.
    #
    # Expected payload format from frontend:
    # {
    #   processed_params: {
    #     body: { '1': 'John', '2': '123 Main St' },
    #     header: {
    #       media_url: 'https://...',
    #       media_type: 'image',
    #       media_name: 'filename.pdf' # Optional, for document templates only
    #     },
    #     buttons: [{ type: 'url', parameter: 'otp123456' }]
    #   }
    # }
    # This gets transformed into WhatsApp API component format:
    # [
    #   { type: 'body', parameters: [...] },
    #   { type: 'header', parameters: [...] },
    #   { type: 'button', sub_type: 'url', parameters: [...] }
    # ]
    template_body[:components] = template_info[:parameters] || []

    template_body
  end

  def whatsapp_reply_context(message)
    reply_to = message.content_attributes[:in_reply_to_external_id]
    return nil if reply_to.blank?

    {
      message_id: reply_to
    }
  end

  def send_interactive_text_message(phone_number, message)
    payload = create_payload_based_on_items(message)

    response = HTTParty.post(
      "#{phone_id_path}/messages",
      headers: api_headers,
      query: graph_credential_params,
      body: {
        messaging_product: 'whatsapp',
        to: phone_number,
        interactive: payload,
        type: 'interactive'
      }.to_json
    )

    process_response(response, message)
  end
end
