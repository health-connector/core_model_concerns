require 'active_support/concern'

module PhoneCoreConcern
  extend ActiveSupport::Concern

  included do
    include LocationModelConcerns::PhoneConcern
    
    embedded_in :person
  end

  class_methods do

  end
end
