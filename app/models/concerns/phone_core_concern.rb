require 'active_support/concern'

module PhoneCoreConcern
  extend ActiveSupport::Concern

  included do
    include LocationModelConcerns::PhoneConcern

    embedded_in :person
    embedded_in :census_member, class_name: "CensusMember"
  end

  class_methods do

  end
end
