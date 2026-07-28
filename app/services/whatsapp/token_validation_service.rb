class Whatsapp::TokenValidationService
  def initialize(access_token, waba_id)
    @access_token = access_token
    @waba_id = waba_id
    @api_client = Whatsapp::FacebookApiClient.new(access_token)
  end

  def perform
    validate_parameters!
    validate_token_waba_access
  end

  private

  def validate_parameters!
    raise ArgumentError, 'Access token is required' if @access_token.blank?
    raise ArgumentError, 'WABA ID is required' if @waba_id.blank?
  end

  def validate_token_waba_access
    token_debug_data = @api_client.debug_token(@access_token)
    waba_scope = extract_waba_scope(token_debug_data)
    verify_waba_authorization(waba_scope)
  end

  def extract_waba_scope(token_data)
    return {} unless token_data.is_a?(Hash) && token_data['data'].is_a?(Hash)

    granular_scopes = token_data.dig('data', 'granular_scopes')
    if granular_scopes.present?
      waba_scope = granular_scopes.find do |scope|
        scope['scope'] == 'whatsapp_business_management' || scope['scope'] == 'whatsapp_business_messaging'
      end
      return waba_scope if waba_scope.present?
    end

    scopes = token_data.dig('data', 'scopes') || []
    return { 'target_ids' => [@waba_id.to_s] } if scopes.include?('whatsapp_business_management') || scopes.include?('whatsapp_business_messaging')

    {}
  end

  def verify_waba_authorization(waba_scope)
    raise 'No WABA scope found in token' if waba_scope.blank?

    authorized_waba_ids = (waba_scope['target_ids'] || []).map(&:to_s)
    return if authorized_waba_ids.include?(@waba_id.to_s)

    raise "Token does not have access to WABA #{@waba_id}. Authorized WABAs: #{authorized_waba_ids}"
  end
end
