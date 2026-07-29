class Api::V1::Integrations::WebhooksController < ApplicationController
  def create
    builder = Integrations::Slack::IncomingMessageBuilder.new(permitted_params)
    response = builder.perform
    render json: response
  end

  private

  # Keys consumed by Integrations::Slack::IncomingMessageBuilder and the unfurl
  # service it enqueues. `blocks` and `files` are Slack-defined nested structures
  # whose inner shape varies by block type, so they are kept intact rather than
  # filtered key by key.
  def permitted_params
    permitted = params.permit(
      :type,
      :challenge,
      event: [
        :type, :subtype, :user, :text, :channel, :thread_ts, :ts,
        :unfurl_id, :source,
        { links: [:url, :domain] }
      ]
    )

    event = params[:event]
    return permitted if event.blank?

    permitted[:event] ||= ActionController::Parameters.new
    %i[blocks files].each do |key|
      permitted[:event][key] = event[key].map { |entry| entry.to_unsafe_h.to_h } if event[key].is_a?(Array)
    end

    permitted
  end
end
