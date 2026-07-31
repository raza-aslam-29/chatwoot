# Sets the HTTP Permissions-Policy response header, which restricts the browser
# features this document and its frames are allowed to use.
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy
#
# Rails' own `config.permissions_policy` DSL is deliberately not used here: as of
# Rails 8.0 it still emits the superseded `Feature-Policy` header (see
# ActionDispatch::Constants::FEATURE_POLICY) with the older space-separated
# syntax, which current browsers no longer honour.
#
# A frame's `allow` attribute can only narrow what the top-level document was
# granted, never widen it, so features used by embedded integrations must be
# delegated here too or the frame is denied them regardless of its own `allow`.
DYTE_ORIGIN = 'https://app.dyte.io'.freeze

PERMISSIONS_POLICY = [
  # Voice messages record from the dashboard itself
  # (app/javascript/dashboard/components/widgets/WootWriter/AudioRecorder.vue);
  # the Dyte meeting frame needs the microphone as well.
  %(microphone=(self "#{DYTE_ORIGIN}")),

  # Camera and screen share are used only by the Dyte meeting frame
  # (app/javascript/dashboard/components-next/message/bubbles/Dyte.vue), which
  # declares allow="camera;microphone;fullscreen;display-capture;...".
  %(camera=("#{DYTE_ORIGIN}")),
  %(display-capture=("#{DYTE_ORIGIN}")),
  %(fullscreen=(self "#{DYTE_ORIGIN}")),
  %(picture-in-picture=(self "#{DYTE_ORIGIN}")),

  # Features the application does not use. Listing them explicitly stops them
  # falling back to the permissive browser default of `*`.
  'accelerometer=()',
  'autoplay=()',
  'encrypted-media=()',
  'geolocation=()',
  'gyroscope=()',
  'hid=()',
  'idle-detection=()',
  'magnetometer=()',
  'midi=()',
  'payment=()',
  'serial=()',
  'usb=()'
].join(', ').freeze

Rails.application.config.action_dispatch.default_headers['Permissions-Policy'] = PERMISSIONS_POLICY
