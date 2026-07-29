module SuperAdmin::FeaturesHelper
  def self.available_features
    YAML.load(ERB.new(Rails.root.join('app/helpers/super_admin/features.yml').read).result).with_indifferent_access
  end

  def self.plan_details
    plan = ChatwootHub.pricing_plan
    quantity = ChatwootHub.pricing_plan_quantity

    if plan == 'premium'
      ActionController::Base.helpers.safe_join(
        ['You are currently on the ', highlight_plan_detail(plan), ' plan with ', highlight_plan_detail("#{quantity} agents"), '.']
      )
    else
      ActionController::Base.helpers.safe_join(
        ['You are currently on the ', highlight_plan_detail(plan), ' edition plan.']
      )
    end
  end

  def self.highlight_plan_detail(value)
    ActionController::Base.helpers.tag.span(value, class: 'font-semibold')
  end
end
