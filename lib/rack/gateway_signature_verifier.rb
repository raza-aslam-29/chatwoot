module Rack
  # Verifies the HMAC signature the Channelx gateway attaches to webhook
  # payloads it forwards to this Chatwoot instance.
  #
  # Scope: applied to request paths that the gateway forwards to (Facebook
  # /bot and WhatsApp webhooks). The check fires only when the gateway
  # signature header is present, so direct-from-Meta deliveries still pass
  # through and are authenticated by their own provider signatures.
  class GatewaySignatureVerifier
    SIGNATURE_HEADER = 'HTTP_X_CHANNELX_SIGNATURE'.freeze
    PROTECTED_PREFIXES = ['/bot', '/webhooks/whatsapp'].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless protected_path?(env['PATH_INFO'])

      signature = env[SIGNATURE_HEADER]
      return @app.call(env) if signature.blank?

      raw_body = read_body(env)
      unless GatewayRegistrationService.verify(raw_body, signature)
        Rails.logger.warn("[GatewaySignature] Rejected request with invalid gateway signature on #{env['PATH_INFO']}")
        return [401, { 'Content-Type' => 'text/plain' }, ['Invalid gateway signature']]
      end

      @app.call(env)
    end

    private

    def protected_path?(path)
      return false if path.blank?

      PROTECTED_PREFIXES.any? { |prefix| path.start_with?(prefix) }
    end

    def read_body(env)
      input = env['rack.input']
      return '' if input.nil?

      input.rewind if input.respond_to?(:rewind)
      body = input.read
      input.rewind if input.respond_to?(:rewind)
      body.to_s
    end
  end
end
