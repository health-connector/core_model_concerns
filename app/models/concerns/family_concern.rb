require 'active_support/concern'

module FamilyConcern
  extend ActiveSupport::Concern

  included do |base|
    require 'autoinc'

    include Mongoid::Document
    include Mongoid::Timestamps
    include Mongoid::Autoinc

    base::IMMEDIATE_FAMILY = IMMEDIATE_FAMILY

    field :version, type: Integer, default: 1
    embeds_many :versions, class_name: self.name, validate: false, cyclic: true, inverse_of: nil

    field :hbx_assigned_id, type: Integer
    increments :hbx_assigned_id, seed: 9999

    field :e_case_id, type: String # Eligibility system foreign key
    field :e_status_code, type: String
    field :application_type, type: String
    field :renewal_consent_through_year, type: Integer # Authorize auto-renewal elibility check through this year (CCYY format)

    field :is_active, type: Boolean, default: true # ApplicationGroup active on the Exchange?
    field :submitted_at, type: DateTime # Date application was created on authority system
    field :updated_by, type: String
    field :status, type: String, default: "" # for aptc block

    belongs_to  :person

    embeds_many :documents, as: :documentable

    def primary_applicant_person
      return nil unless primary_applicant.present?
      primary_applicant.person
    end

    # The {FamilyMember} who is head and 'owner' of this family instance.
    #
    # @example Who is the primary applicant for this family?
    #   model.primary_applicant
    #
    # @return [ FamilyMember ] the designated head of this family
    def primary_applicant
      family_members.detect { |family_member| family_member.is_primary_applicant? && family_member.is_active? }
    end

    # Get all active {FamilyMember FamilyMembers}
    #
    # @example Who are the active members for this family?
    #   model.active_family_members
    #
    # @return [ Array<FamilyMember> ] the active members of this family
    def active_family_members
      family_members.find_all { |family_member| family_member.is_active? }
    end

    # Get the {FamilyMember} associated with this {Person}
    #
    # @example Which {FamilyMember} references this {Person}?
    #   model.find_family_member_by_person
    #
    # @param person [ Person ] the {Person} to match
    #
    # @return [ FamilyMember ] the family member who matches this person
    def find_family_member_by_person(person)
      family_members.detect { |family_member| family_member.person_id.to_s == person._id.to_s }
    end

    # Create a {FamilyMember} referencing this {Person}
    #
    # @param [ Person ] person The person to add to the family.
    # @param [ Hash ] opts The options to create the family member.
    # @option opts [ true, false ] :is_primary_applicant (false) This person is the primary family member
    # @option opts [ true, false ] :is_coverage_applicant (true) This person may enroll in coverage
    # @option opts [ true, false ] :is_consent_applicant (false) This person is consent applicant
    #
    def add_family_member(person, **opts)
      is_primary_applicant  = opts[:is_primary_applicant]  || false
      is_coverage_applicant = opts[:is_coverage_applicant] || true
      is_consent_applicant  = opts[:is_consent_applicant]  || false

      existing_family_member = family_members.detect { |fm| fm.person_id.to_s == person.id.to_s }

      if existing_family_member
        active_household.add_household_coverage_member(existing_family_member)
        existing_family_member.is_active = true
        return existing_family_member
      end

      family_member = family_members.build(
          person: person,
          is_primary_applicant: is_primary_applicant,
          is_coverage_applicant: is_coverage_applicant,
          is_consent_applicant: is_consent_applicant
        )

      active_household.add_household_coverage_member(family_member)
      family_member
    end

    # Remove {FamilyMember} referenced by this {Person}
    #
    # @param [ Person ] person The {Person} to remove from the family.
    def remove_family_member(person)
      family_member = find_family_member_by_person(person)
      if family_member.present?
        family_member.is_active = false
        active_household.remove_family_member(family_member)
      end

      family_member
    end

    # Determine if {Person} is a member of this family
    #
    # @example Is this person a family member?
    #   model.person_is_family_member?(person)
    #
    # @return [ true, false ] true if the person is in the family, false if the person isn't in the family
    def person_is_family_member?(person)
      find_family_member_by_person(person).present?
    end

    # Get list of family members who are not the primary applicant
    #
    # @example Which family members are non-primary applicants?
    #   model.dependents
    #
    # @return [ Array<FamilyMember> ] the list of dependents
    def dependents
      family_members.reject(&:is_primary_applicant)
    end

    def people_relationship_map
      map = Hash.new
      people.each do |person|
        map[person] = person_relationships.detect { |r| r.object_person == person.id }.relationship_kind
      end
      map
    end

    def is_active?
      self.is_active
    end

    def build_from_person(person)
      add_family_member(person, is_primary_applicant: true)
      person.person_relationships.each { |kin| add_family_member(kin.relative) }
      self
    end

    def relate_new_member(person, relationship)
      primary_applicant_person.ensure_relationship_with(person, relationship)
      add_family_member(person)
    end

    def find_matching_inactive_member(personish)
      inactive_members = family_members.reject(&:is_active)
      return nil if inactive_members.blank?
      if !personish.ssn.blank?
        inactive_members.detect { |mem| mem.person.ssn == personish.ssn }
      else
        return nil if personish.dob.blank?
        search_dob = personish.dob.strftime("%m/%d/%Y")
        inactive_members.detect do |mem|
          mp = mem.person
          mem_dob = mem.dob.blank? ? nil : mem.dob.strftime("%m/%d/%Y")
          (personish.last_name.downcase.strip == mp.last_name.downcase.strip) &&
            (personish.first_name.downcase.strip == mp.first_name.downcase.strip) &&
            (search_dob == mem_dob)
        end
      end
    end

    class << self
      # Get all families where this person is a member
      # @param person [ Person ] Person to match
      # @return [ Array<Family> ] The families where this person is a member
      def find_all_by_person(person)
        where("family_members.person_id" => person.id)
      end

      # Get the family where this person is the primary applicant
      # @param person [ Person ] Person to match
      # @return [ Array<Family> ] The families where this person is primary applicant
      def find_primary_applicant_by_person(person)
        find_all_by_person(person).select() { |f| f.primary_applicant.person.id.to_s == person.id.to_s }
      end
    end
  end

  class_methods do
    IMMEDIATE_FAMILY = %w(self spouse life_partner child ward foster_child adopted_child stepson_or_stepdaughter stepchild domestic_partner)

  end
end
