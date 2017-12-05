require 'active_support/concern'

module GeographicRatingAreaConcern
  extend ActiveSupport::Concern

  included do
    include LocationModelConcerns::GeographicRatingAreaConcern
    
    embedded_in :benefit_sponsorship
  end

  class_methods do

  end
end
