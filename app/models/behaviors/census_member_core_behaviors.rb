require 'active_support/concern'

module Behaviors
  module CensusMemberCoreBehaviors
    extend ActiveSupport::Concern

    included do |base|
      include Mongoid::Document
      include Mongoid::Timestamps
      include Behaviors::UnsetableSparseFields

      field :first_name, type: String
      field :middle_name, type: String
      field :last_name, type: String
      field :name_sfx, type: String

      field :encrypted_ssn, type: String
      field :dob, type: Date
      field :gender, type: String

      field :employee_relationship, type: String
      field :employer_assigned_family_id, type: String

      validates_presence_of :first_name, :last_name, :dob

      validates :gender,
        allow_blank: false,
        inclusion: { in: GENDER_KINDS, message: "must be selected" }
        after_validation :move_encrypted_ssn_errors

      def move_encrypted_ssn_errors
        deleted_messages = errors.delete(:encrypted_ssn)
        if !deleted_messages.blank?
          deleted_messages.each do |dm|
            errors.add(:ssn, dm)
          end
        end
        true
      end

      def ssn_changed?
        encrypted_ssn_changed?
      end

      # Strip non-numeric chars from ssn
      # SSN validation rules, see: http://www.ssa.gov/employer/randomizationfaqs.html#a0=12
      def ssn=(new_ssn)
        if !new_ssn.blank?
          write_attribute(:encrypted_ssn, self.class.encrypt_ssn(new_ssn))
        else
          unset_sparse("encrypted_ssn")
        end
      end

      def ssn
        ssn_val = read_attribute(:encrypted_ssn)
        if !ssn_val.blank?
          self.class.decrypt_ssn(ssn_val)
        else
          nil
        end
      end

      def gender=(val)
        if val.blank?
          write_attribute(:gender, nil)
          return
        end
        write_attribute(:gender, val.downcase)
      end

      def dob_string
        self.dob.blank? ? "" : self.dob.strftime("%Y%m%d")
      end

      def date_of_birth
        self.dob.blank? ? nil : self.dob.strftime("%m/%d/%Y")
      end

      def date_of_birth=(val)
        self.dob = Date.strptime(val, "%Y-%m-%d").to_date rescue nil
      end

      def full_name
        [first_name, middle_name, last_name, name_sfx].compact.join(" ")
      end
    end

    class_methods do
      GENDER_KINDS = %W(male female)

      def encrypt_ssn(val)
        if val.blank?
          return nil
        end
        ssn_val = val.to_s.gsub(/\D/, '')
        ::SymmetricEncryption.encrypt(ssn_val)
      end

      def decrypt_ssn(val)
        ::SymmetricEncryption.decrypt(val)
      end
    end
  end
end
