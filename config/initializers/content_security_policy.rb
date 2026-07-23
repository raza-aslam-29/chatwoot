# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy
# For further information see the following documentation
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy

Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src    :self, :data, :https
  policy.img_src     :self, :data, :https
  policy.object_src  :none
  policy.script_src  :self
  policy.style_src   :self, :unsafe_inline
  policy.connect_src :self, :https, :wss
  policy.frame_ancestors :self
  policy.base_uri    :self

  # Allow @vite/client to hot reload changes in development
  if Rails.env.development?
    policy.script_src(*policy.script_src, :unsafe_eval, "http://#{ViteRuby.config.host_with_port}")
    policy.connect_src(*policy.connect_src, "ws://#{ViteRuby.config.host_with_port}")
  end
end

# Generate a per-request nonce so inline scripts in layouts we control can be
# allowlisted without falling back to :unsafe_inline.
Rails.application.config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
Rails.application.config.content_security_policy_nonce_directives = %w[script-src]

# The application still renders inline scripts from layouts and admin-configured
# DASHBOARD_SCRIPTS that are not nonce-tagged, so the app-wide policy stays in
# report-only mode while those violations are observed. Controllers that render
# fully nonce-tagged layouts opt into enforcement individually.
Rails.application.config.content_security_policy_report_only = true
