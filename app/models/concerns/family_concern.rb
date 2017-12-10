require 'active_support/concern'

module FamilyConcern
  extend ActiveSupport::Concern

  included do |base|
    include Mongoid::Document
    include Mongoid::Timestamps
    
    base::IMMEDIATE_FAMILY = IMMEDIATE_FAMILY
  end

  class_methods do
    IMMEDIATE_FAMILY = %w(self spouse life_partner child ward foster_child adopted_child stepson_or_stepdaughter stepchild domestic_partner)

  end
end
