# frozen_string_literal: true

class Integrations::Facebook::MessageCreator
  attr_reader :response

  def initialize(response)
    @response = response
  end

  def perform
    # begin
    if agent_message_via_echo?
      create_agent_message
    else
      create_contact_message
    end
    # rescue => e
    # ChatwootExceptionTracker.new(e).capture_exception
    # end
  end

  private

  def agent_message_via_echo?
    # An echo is an agent message from the page (sent directly via FB mobile/web
    # messenger) that we must recreate — UNLESS it is our own outbound send echoing
    # back, in which case it would be a duplicate.
    response.echo? && !sent_from_chatwoot?
  end

  # Recognise our own sends without relying on FB_APP_ID. In gateway mode the Meta
  # app id lives on the gateway, so the legacy app_id check (sent_from_chatwoot_app?)
  # can't match and every echo would be duplicated. Our outbound send already stored
  # the Send API message_id as the message source_id, so a matching source_id means
  # this echo is ours and should be dropped.
  def sent_from_chatwoot?
    response.sent_from_chatwoot_app? || echo_already_recorded?
  end

  def echo_already_recorded?
    return false if response.identifier.blank?

    Channel::FacebookPage.where(page_id: response.sender_id).any? do |page|
      page.inbox.messages.exists?(source_id: response.identifier)
    end
  end

  def create_agent_message
    Channel::FacebookPage.where(page_id: response.sender_id).each do |page|
      mb = Messages::Facebook::MessageBuilder.new(response, page.inbox, outgoing_echo: true)
      mb.perform
    end
  end

  def create_contact_message
    Channel::FacebookPage.where(page_id: response.recipient_id).each do |page|
      mb = Messages::Facebook::MessageBuilder.new(response, page.inbox)
      mb.perform
    end
  end
end
