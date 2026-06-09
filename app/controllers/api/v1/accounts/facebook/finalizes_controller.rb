class Api::V1::Accounts::Facebook::FinalizesController < Api::V1::Accounts::BaseController
  require 'net/http'

  FACEBOOK_TOKEN_URL = 'https://graph.facebook.com/v18.0/oauth/access_token'.freeze

  def create
    gateway_url = ENV.fetch('CHANNELX_GATEWAY_URL', '')
    
    # Must strictly match the redirect URI registered in Meta App Dashboard
    # and the one used to generate the auth code.
    callback_redirect_uri = gateway_url.present? ? "#{gateway_url}/facebook/callback" : "#{base_url}/facebook/callback"
    app_id = GlobalConfigService.load('FB_APP_ID', '')
    app_secret = GlobalConfigService.load('FB_APP_SECRET', '')

    # 1. Exchange the code for a short-lived token
    token_response = exchange_code_for_token(params[:code], callback_redirect_uri, app_id, app_secret)
    
    if token_response['error'].present?
      Rails.logger.error "Meta Token Exchange Error: #{token_response['error'].inspect}"
      render json: { error: token_response['error']['message'] }, status: :unprocessable_entity
      return
    end
    
    short_lived_token = token_response['access_token']

    # 2. Exchange short-lived token for a long-lived token via Koala
    long_lived_token = exchange_for_long_lived_token(short_lived_token, app_id, app_secret)

    render json: { user_access_token: long_lived_token }
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def exchange_code_for_token(code, redirect_uri, app_id, app_secret)
    uri = URI(FACEBOOK_TOKEN_URL)
    response = Net::HTTP.post_form(uri, {
                                     'client_id' => app_id,
                                     'client_secret' => app_secret,
                                     'redirect_uri' => redirect_uri,
                                     'code' => code
                                   })
    JSON.parse(response.body)
  end

  def exchange_for_long_lived_token(short_token, app_id, app_secret)
    koala = Koala::Facebook::OAuth.new(app_id, app_secret)
    koala.exchange_access_token_info(short_token)['access_token']
  end

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end
end
