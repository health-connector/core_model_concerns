require 'active_support/concern'

module CensusMemberConcern
  extend ActiveSupport::Concern

  included do
    include Behaviors::CensusMemberCoreBehaviors
    include Behaviors::UnsetableSparseFields
    include Behaviors::StrippedNames

    validates_with Validations::DateRangeValidator

    embeds_one :address
    accepts_nested_attributes_for :address, reject_if: :all_blank, allow_destroy: true

    embeds_one :email
    accepts_nested_attributes_for :email, allow_destroy: true

    validates :ssn,
      length: { minimum: 9, maximum: 9, message: "SSN must be 9 digits" },
      allow_blank: true,
      numericality: true

    validate :date_of_birth_is_past

    def age_on(date)
      age = date.year - dob.year
      if date.month == dob.month
        age -= 1 if date.day < dob.day
      else
        age -= 1 if date.month < dob.month
      end
      age
    end

    class << self
    end

    private

      def date_of_birth_is_past
        return unless self.dob.present?
        errors.add(:dob, "future date: #{self.dob} is invalid date of birth") if TimeKeeper.date_of_record < self.dob
      end
  end

  class_methods do
  end
end
