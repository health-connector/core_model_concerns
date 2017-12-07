require 'active_support/concern'

module UserConcern
  extend ActiveSupport::Concern

  included do
    include Mongoid::Document
    include Mongoid::Timestamps
  end

  class_methods do

  end
end
