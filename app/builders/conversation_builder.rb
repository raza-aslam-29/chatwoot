class ConversationBuilder
  pattr_initialize [:params!, :contact_inbox!]

  def perform
    look_up_exising_conversation || create_new_conversation
  end

  private

  def look_up_exising_conversation
    return unless @contact_inbox.inbox.lock_to_single_conversation?

    @contact_inbox.conversations.last
  end

  def create_new_conversation
    ::Conversation.create!(conversation_params)
  end

  def conversation_params
    # These are free-form jsonb attribute bags with customer-defined keys, so an exact
    # allowlist is not possible. They are assigned to their own columns below rather than
    # mass-assigned, so converting to a plain hash is enough.
    additional_attributes = permitted_attribute_bag(params[:additional_attributes])
    custom_attributes = permitted_attribute_bag(params[:custom_attributes])
    status = params[:status].present? ? { status: params[:status] } : {}

    # TODO: temporary fallback for the old bot status in conversation, we will remove after couple of releases
    # commenting this out to see if there are any errors, if not we can remove this in subsequent releases
    # status = { status: 'pending' } if status[:status] == 'bot'
    {
      account_id: @contact_inbox.inbox.account_id,
      inbox_id: @contact_inbox.inbox_id,
      contact_id: @contact_inbox.contact_id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: additional_attributes,
      custom_attributes: custom_attributes,
      snoozed_until: params[:snoozed_until],
      assignee_id: params[:assignee_id],
      team_id: params[:team_id]
    }.merge(status)
  end

  def permitted_attribute_bag(attributes)
    return {} if attributes.blank?
    return attributes.to_unsafe_h.to_h if attributes.respond_to?(:to_unsafe_h)

    attributes.to_h
  end
end
