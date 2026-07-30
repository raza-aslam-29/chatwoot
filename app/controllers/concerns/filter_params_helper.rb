module FilterParamsHelper
  extend ActiveSupport::Concern

  # Keys consumed by FilterService and its subclasses. `values` is permitted as both a
  # scalar and an array since filters accept either (eg. 'en' or %w[resolved]).
  FILTER_PAYLOAD_KEYS = [
    :attribute_key,
    :filter_operator,
    :query_operator,
    :custom_attribute_type,
    { values: [] },
    :values
  ].freeze

  private

  def permitted_filter_params
    params.permit(:page, payload: FILTER_PAYLOAD_KEYS)
  end
end
