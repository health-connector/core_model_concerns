require 'active_support/concern'

module PersonConcern
  extend ActiveSupport::Concern

  included do |base|
    include ConfigAcaLocationConcern
    include ConfigSiteDescriptionConcern
    include UnsetableSparseFieldsConcern
    include Mongoid::Document
    include Mongoid::Timestamps
    include Mongoid::Versioning

    base::GENDER_KINDS = GENDER_KINDS
    base::IDENTIFYING_INFO_ATTRIBUTES = IDENTIFYING_INFO_ATTRIBUTES
    base::ADDRESS_CHANGE_ATTRIBUTES = ADDRESS_CHANGE_ATTRIBUTES
    base::RELATIONSHIP_CHANGE_ATTRIBUTES = RELATIONSHIP_CHANGE_ATTRIBUTES

    belongs_to :user

    field :hbx_id, type: String
    field :name_pfx, type: String
    field :first_name, type: String
    field :middle_name, type: String
    field :last_name, type: String
    field :name_sfx, type: String
    field :full_name, type: String
    field :alternate_name, type: String

    # Sub-model in-common attributes
    field :encrypted_ssn, type: String
    field :dob, type: Date
    field :gender, type: String
    field :date_of_death, type: Date
    field :dob_check, type: Boolean

    field :is_incarcerated, type: Boolean

    field :is_disabled, type: Boolean
    field :ethnicity, type: Array
    field :race, type: String
    field :tribal_id, type: String

    field :is_tobacco_user, type: String, default: "unknown"
    field :language_code, type: String

    field :no_dc_address, type: Boolean, default: false
    field :no_dc_address_reason, type: String, default: ""

    field :is_active, type: Boolean, default: true
    field :updated_by, type: String
    field :no_ssn, type: String #ConsumerRole TODO TODOJF

    attr_writer :us_citizen, :naturalized_citizen, :indian_tribe_member, :eligible_immigration_status

    embeds_one :inbox, as: :recipient

    embeds_many :person_relationships, cascade_callbacks: true, validate: true
    embeds_many :addresses, cascade_callbacks: true, validate: true
    embeds_many :phones, cascade_callbacks: true, validate: true
    embeds_many :documents, as: :documentable

    accepts_nested_attributes_for :person_relationships, :phones
    accepts_nested_attributes_for :phones, :reject_if => Proc.new { |addy| Phone.new(addy).blank? }
    accepts_nested_attributes_for :addresses, :reject_if => Proc.new { |addy| Address.new(addy).blank? }

    validates_presence_of :first_name, :last_name

    validates :ssn,
      length: { minimum: 9, maximum: 9, message: "SSN must be 9 digits" },
      numericality: true,
      allow_blank: true

    validates :encrypted_ssn, uniqueness: true, allow_blank: true

    validates :gender,
        allow_blank: true,
        inclusion: { in: base::GENDER_KINDS, message: "%{value} is not a valid gender" }

    validate :date_functional_validations
    validate :is_ssn_composition_correct?

    after_validation :move_encrypted_ssn_errors

    before_save :generate_hbx_id
    before_save :update_full_name
    before_save :strip_empty_fields

    after_create :create_inbox

    index({hbx_id: 1}, {sparse:true, unique: true})
    index({user_id: 1}, {sparse:true, unique: true})

    index({last_name:  1})
    index({first_name: 1})
    index({last_name: 1, first_name: 1})
    index({first_name: 1, last_name: 1})
    index({first_name: 1, last_name: 1, hbx_id: 1, encrypted_ssn: 1}, {name: "person_searching_index"})

    index({encrypted_ssn: 1}, {sparse: true, unique: true})
    index({dob: 1}, {sparse: true})
    index({dob: 1, encrypted_ssn: 1})

    index({last_name: 1, dob: 1}, {sparse: true})

    index({"person_relationship.relative_id" =>  1})

    scope :by_hbx_id, ->(person_hbx_id) { where(hbx_id: person_hbx_id) }
    scope :active,    ->{ where(is_active: true) }
    scope :inactive,  ->{ where(is_active: false) }
    scope :matchable, ->(ssn, dob, last_name) { where(encrypted_ssn: Person.encrypt_ssn(ssn), dob: dob, last_name: last_name) }
    scope :by_ssn,    ->(ssn) { where(encrypted_ssn: Person.encrypt_ssn(ssn)) }

    def full_name
      @full_name = [name_pfx, first_name, middle_name, last_name, name_sfx].compact.join(" ")
    end

    def gender=(new_gender)
      write_attribute(:gender, new_gender.to_s.downcase)
    end

    def us_citizen=(val)
      @us_citizen = (val.to_s == "true")
      @naturalized_citizen = false if val.to_s == "false"
    end

    def naturalized_citizen=(val)
      @naturalized_citizen = (val.to_s == "true")
    end

    def indian_tribe_member=(val)
      @indian_tribe_member = (val.to_s == "true")
    end

    def eligible_immigration_status=(val)
      @eligible_immigration_status = (val.to_s == "true")
    end

    def date_of_birth
      self.dob.blank? ? nil : self.dob.strftime("%m/%d/%Y")
    end

    def date_of_birth=(val)
      self.dob = Date.strptime(val, "%m/%d/%Y").to_date rescue nil
    end

    def us_citizen
      return @us_citizen if !@us_citizen.nil?
      return nil if citizen_status.blank?
      @us_citizen ||= ::ConsumerRole::US_CITIZEN_STATUS_KINDS.include?(citizen_status)
    end

    def naturalized_citizen
      return @naturalized_citizen if !@naturalized_citizen.nil?
      return nil if citizen_status.blank?
      @naturalized_citizen ||= (::ConsumerRole::NATURALIZED_CITIZEN_STATUS == citizen_status)
    end

    def indian_tribe_member
      return @indian_tribe_member if !@indian_tribe_member.nil?
      return nil if citizen_status.blank?
      @indian_tribe_member ||= (::ConsumerRole::INDIAN_TRIBE_MEMBER_STATUS == citizen_status)
    end

    def eligible_immigration_status
      return @eligible_immigration_status if !@eligible_immigration_status.nil?
      return nil if us_citizen.nil?
      return nil if @us_citizen
      return nil if citizen_status.blank?
      @eligible_immigration_status ||= (::ConsumerRole::ALIEN_LAWFULLY_PRESENT_STATUS == citizen_status)
    end

    def assign_citizen_status
      if indian_tribe_member
        self.citizen_status = ::ConsumerRole::INDIAN_TRIBE_MEMBER_STATUS
      elsif naturalized_citizen
        self.citizen_status = ::ConsumerRole::NATURALIZED_CITIZEN_STATUS
      elsif us_citizen
        self.citizen_status = ::ConsumerRole::US_CITIZEN_STATUS
      elsif eligible_immigration_status
        self.citizen_status = ::ConsumerRole::ALIEN_LAWFULLY_PRESENT_STATUS
      elsif (!eligible_immigration_status.nil?)
        self.citizen_status = ::ConsumerRole::NOT_LAWFULLY_PRESENT_STATUS
      elsif
        self.errors.add(:base, "Citizenship status can't be nil.")
      end
    end

    # Strip non-numeric chars from ssn
    # SSN validation rules, see: http://www.ssa.gov/employer/randomizationfaqs.html#a0=12
    def ssn=(new_ssn)
      if !new_ssn.blank?
        write_attribute(:encrypted_ssn, Person.encrypt_ssn(new_ssn))
      else
        unset_sparse("encrypted_ssn")
      end
    end

    def residency_eligible?
      no_dc_address and no_dc_address_reason.present?
    end

    def is_dc_resident?
      return false if no_dc_address == true && no_dc_address_reason.blank?
      return true if no_dc_address == true && no_dc_address_reason.present?

      address_to_use = addresses.collect(&:kind).include?('home') ? 'home' : 'mailing'
      addresses.each{|address| return true if address.kind == address_to_use && address.state == aca_state_abbreviation}
      return false
    end

    private
      def create_inbox
        welcome_subject = "Welcome to #{site_short_name}"
        welcome_body = "#{site_short_name} is the #{aca_state_name}'s on-line marketplace to shop, compare, and select health insurance that meets your health needs and budgets."
        mailbox = Inbox.create(recipient: self)
        mailbox.messages.create(subject: welcome_subject, body: welcome_body, from: "#{site_short_name}")
      end

      def strip_empty_fields
        if encrypted_ssn.blank?
          unset_sparse("encrypted_ssn")
        end
        if user_id.blank?
          unset_sparse("user_id")
        end
      end

      def generate_hbx_id
        write_attribute(:hbx_id, HbxIdGenerator.generate_member_id) if hbx_id.blank?
      end

      def update_full_name
        full_name
      end
  end

  class_methods do
    GENDER_KINDS = %W(male female)
    IDENTIFYING_INFO_ATTRIBUTES = %w(first_name last_name ssn dob)
    ADDRESS_CHANGE_ATTRIBUTES = %w(addresses phones emails)
    RELATIONSHIP_CHANGE_ATTRIBUTES = %w(person_relationships)

    def find_by_ssn(ssn)
      Person.where(encrypted_ssn: Person.encrypt_ssn(ssn)).first
    end

    def match_existing_person(personish)
      return nil if personish.ssn.blank?
      Person.where(:encrypted_ssn => encrypt_ssn(personish.ssn), :dob => personish.dob).first
    end

    def default_search_order
      [[:last_name, 1],[:first_name, 1]]
    end

    def search_hash(s_str)
      clean_str = s_str.strip
      s_rex = Regexp.new(Regexp.escape(clean_str), true)
      {
        "$or" => ([
          {"first_name" => s_rex},
          {"last_name" => s_rex},
          {"hbx_id" => s_rex},
          {"encrypted_ssn" => encrypt_ssn(s_rex)}
        ] + additional_exprs(clean_str))
      }
    end

    def additional_exprs(clean_str)
      additional_exprs = []
      if clean_str.include?(" ")
        parts = clean_str.split(" ").compact
        first_re = Regexp.new(Regexp.escape(parts.first), true)
        last_re = Regexp.new(Regexp.escape(parts.last), true)
        additional_exprs << {:first_name => first_re, :last_name => last_re}
      end
      additional_exprs
    end

    def encrypt_ssn(val)
      if val.blank?
        return nil
      end
      ssn_val = val.to_s.gsub(/\D/, '')
      SymmetricEncryption.encrypt(ssn_val)
    end

    def decrypt_ssn(val)
      SymmetricEncryption.decrypt(val)
    end

    def match_by_id_info(options)
      ssn_query = options[:ssn]
      dob_query = options[:dob]
      last_name = options[:last_name]
      first_name = options[:first_name]

      raise ArgumentError, "must provide an ssn or first_name/last_name/dob or both" if (ssn_query.blank? && (dob_query.blank? || last_name.blank? || first_name.blank?))

      matches = Array.new
      matches.concat Person.active.where(encrypted_ssn: encrypt_ssn(ssn_query), dob: dob_query).to_a unless ssn_query.blank?
      #matches.concat Person.where(last_name: last_name, dob: dob_query).active.to_a unless (dob_query.blank? || last_name.blank?)
      if first_name.present? && last_name.present? && dob_query.present?
        first_exp = /^#{first_name}$/i
        last_exp = /^#{last_name}$/i
        matches.concat Person.where(dob: dob_query, last_name: last_exp, first_name: first_exp).to_a.select{|person| person.ssn.blank? || ssn_query.blank?}
      end
      matches.uniq
    end
  end

  def first_name_last_name_and_suffix
    [first_name, last_name, name_sfx].compact.join(" ")
    case name_sfx
      when "ii" ||"iii" || "iv" || "v"
        [first_name.capitalize, last_name.capitalize, name_sfx.upcase].compact.join(" ")
      else
        [first_name.capitalize, last_name.capitalize, name_sfx].compact.join(" ")
      end
  end

  def age_on(date)
    age = date.year - dob.year
    if date.month < dob.month || (date.month == dob.month && date.day < dob.day)
      age - 1
    else
      age
    end
  end

  def dob_to_string
    dob.blank? ? "" : dob.strftime("%Y%m%d")
  end

  def is_active?
    is_active
  end

  def ssn_changed?
    encrypted_ssn_changed?
  end

  def ssn
    ssn_val = read_attribute(:encrypted_ssn)
    if !ssn_val.blank?
      Person.decrypt_ssn(ssn_val)
    else
      nil
    end
  end

  def contact_phones
    phones.reject { |ph| ph.full_phone_number.blank? }
  end

  def work_phone
    phones.detect { |phone| phone.kind == "work" } || main_phone
  end

  def main_phone
    phones.detect { |phone| phone.kind == "main" }
  end

  def home_phone
    phones.detect { |phone| phone.kind == "home" }
  end

  def mobile_phone
    phones.detect { |phone| phone.kind == "mobile" }
  end

  def work_phone_or_best
    best_phone  = work_phone || mobile_phone || home_phone
    best_phone ? best_phone.full_phone_number : nil
  end

  def home_address
    addresses.detect { |adr| adr.kind == "home" }
  end

  def mailing_address
    addresses.detect { |adr| adr.kind == "mailing" } || home_address
  end

  def has_mailing_address?
    addresses.any? { |adr| adr.kind == "mailing" }
  end

  def relatives
    person_relationships.reject do |p_rel|
      p_rel.relative_id.to_s == self.id.to_s
    end.map(&:relative)
  end

  def find_relationship_with(other_person)
    if self.id == other_person.id
      "self"
    else
      person_relationship_for(other_person).try(:kind)
    end
  end

  def person_relationship_for(other_person)
    person_relationships.detect do |person_relationship|
      person_relationship.relative_id == other_person.id
    end
  end

  def ensure_relationship_with(person, relationship)
    return if person.blank?
    existing_relationship = self.person_relationships.detect do |rel|
      rel.relative_id.to_s == person.id.to_s
    end
    if existing_relationship
      existing_relationship.update_attributes(:kind => relationship)
    else
      self.person_relationships << PersonRelationship.new({
        :kind => relationship,
        :relative_id => person.id
      })
    end
  end

  private
    def is_ssn_composition_correct?
      # Invalid compositions:
      #   All zeros or 000, 666, 900-999 in the area numbers (first three digits);
      #   00 in the group number (fourth and fifth digit); or
      #   0000 in the serial number (last four digits)

      if ssn.present?
        invalid_area_numbers = %w(000 666)
        invalid_area_range = 900..999
        invalid_group_numbers = %w(00)
        invalid_serial_numbers = %w(0000)

        return false if ssn.to_s.blank?
        return false if invalid_area_numbers.include?(ssn.to_s[0,3])
        return false if invalid_area_range.include?(ssn.to_s[0,3].to_i)
        return false if invalid_group_numbers.include?(ssn.to_s[3,2])
        return false if invalid_serial_numbers.include?(ssn.to_s[5,4])
      end

      true
    end

    def move_encrypted_ssn_errors
      deleted_messages = errors.delete(:encrypted_ssn)
      if !deleted_messages.blank?
        deleted_messages.each do |dm|
          errors.add(:ssn, dm)
        end
      end
      true
    end

    # Verify basic date rules
    def date_functional_validations
      date_of_birth_is_past
      date_of_death_is_blank_or_past
      date_of_death_follows_date_of_birth
    end

    def date_of_death_is_blank_or_past
      return unless self.date_of_death.present?
      errors.add(:date_of_death, "future date: #{self.date_of_death} is invalid date of death") if TimeKeeper.date_of_record < self.date_of_death
    end

    def date_of_birth_is_past
      return unless self.dob.present?
      errors.add(:dob, "future date: #{self.dob} is invalid date of birth") if TimeKeeper.date_of_record < self.dob
    end

    def date_of_death_follows_date_of_birth
      return unless self.date_of_death.present? && self.dob.present?

      if self.date_of_death < self.dob
        errors.add(:date_of_death, "date of death cannot preceed date of birth")
        errors.add(:dob, "date of birth cannot follow date of death")
      end
    end
end
