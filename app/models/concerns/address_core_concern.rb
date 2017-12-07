require 'active_support/concern'

module AddressCoreConcern
  extend ActiveSupport::Concern

  included do
    include LocationModelConcerns::AddressConcern
    
    embedded_in :person
  end

  class_methods do

  end
end
