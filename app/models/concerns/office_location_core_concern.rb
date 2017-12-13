require 'active_support/concern'

module OfficeLocationCoreConcern
  extend ActiveSupport::Concern

  included do
    include LocationModelConcerns::OfficeLocationConcern

    embedded_in :organization
  end

  class_methods do
    ## class methods and constants go here
  end

  def parent
    self.organization
  end
end
