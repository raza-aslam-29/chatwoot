module Channelable
  extend ActiveSupport::Concern
  included do
    validates :account_id, presence: true
    belongs_to :account
    has_one :inbox, as: :channel, dependent: :destroy_async, touch: true
    after_update :create_audit_log_entry
    after_destroy :unregister_from_gateway
  end

  def create_audit_log_entry; end

  # Channels that register routes with the Channelx gateway override this to return the
  # identifier(s) the gateway knows them by, so deleting the inbox (which destroys the
  # channel via Inbox `dependent: :destroy`) also removes the mapping from the gateway.
  # Default: nothing to unregister.
  def gateway_unregister_routes
    []
  end

  def unregister_from_gateway
    return if ENV.fetch('CHANNELX_GATEWAY_URL', '').blank?

    gateway_unregister_routes.each do |route|
      GatewayRegistrationService.new(
        platform_type: route[:platform_type],
        platform_id: route[:platform_id]
      ).unregister
    end
  rescue StandardError => e
    Rails.logger.error "[GatewayUnregister] Failed for #{self.class.name}: #{e.message}"
  end
end

Channelable.prepend_mod_with('Channelable')
