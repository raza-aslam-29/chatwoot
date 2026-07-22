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

# Start in report-only mode so legitimate resources (Vite assets, websockets,
# inline scripts) are not blocked while violations are observed in the browser
# console. Once no legitimate resources are reported as blocked, remove this
# line to enforce the policy.
Rails.application.config.content_security_policy_report_only = true
