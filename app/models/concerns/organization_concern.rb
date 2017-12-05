require 'active_support/concern'

module OrganizationConcern
  extend ActiveSupport::Concern

  included do
    include Mongoid::Document
    include Mongoid::Timestamps
    include Mongoid::Versioning
    
    embeds_one :hbx_profile, cascade_callbacks: true, validate: true
    embeds_many :office_locations, cascade_callbacks: true, validate: true

    accepts_nested_attributes_for :office_locations, :hbx_profile
  
    before_save :generate_hbx_id
    after_update :legal_name_or_fein_change_attributes,:if => :check_legal_name_or_fein_changed?
    after_save :validate_and_send_denial_notice
  
    field :hbx_id, type: String
    field :issuer_assigned_id, type: String

    # Registered legal name
    field :legal_name, type: String

    # Doing Business As (alternate name)
    field :dba, type: String

    # Federal Employer ID Number
    field :fein, type: String

    # Web URL
    field :home_page, type: String

    field :is_active, type: Boolean

    field :is_fake_fein, type: Boolean

    # User or Person ID who created/updated
    field :updated_by, type: BSON::ObjectId
    
    validates_presence_of :legal_name, :fein, :office_locations #, :updated_by

    validates :fein,
      length: { is: 9, message: "%{value} is not a valid FEIN" },
      numericality: true,
      uniqueness: true

    validate :office_location_kinds

    index({ hbx_id: 1 }, { unique: true })
    index({ legal_name: 1 })
    index({ dba: 1 }, {sparse: true})
    index({ fein: 1 }, { unique: true })
    index({ is_active: 1 })
  
    default_scope                               ->{ order("legal_name ASC") }
    scope :datatable_search, ->(query) { self.where({"$or" => ([{"legal_name" => Regexp.compile(Regexp.escape(query), true)}, {"fein" => Regexp.compile(Regexp.escape(query), true)}, {"hbx_id" => Regexp.compile(Regexp.escape(query), true)}])}) }
  
    def validate_and_send_denial_notice
      if employer_profile.present? && primary_office_location.present? && primary_office_location.address.present?
        employer_profile.validate_and_send_denial_notice
      end
    end

    def generate_hbx_id
      write_attribute(:hbx_id, HbxIdGenerator.generate_organization_id) if hbx_id.blank?
    end
    
    # Strip non-numeric characters
    def fein=(new_fein)
      write_attribute(:fein, new_fein.to_s.gsub(/\D/, ''))
    end

    def primary_office_location
      office_locations.detect(&:is_primary?)
    end
    
    def office_location_kinds
      location_kinds = self.office_locations.select{|l| !l.persisted?}.flat_map(&:address).compact.flat_map(&:kind)
      # should validate only office location which are not persisted AND kinds ie. primary, mailing, branch
      return if no_primary = location_kinds.detect{|kind| kind == 'work' || kind == 'home'}
      unless location_kinds.empty?
        if location_kinds.count('primary').zero?
          errors.add(:base, "must select one primary address")
        elsif location_kinds.count('primary') > 1
          errors.add(:base, "can't have multiple primary addresses")
        elsif location_kinds.count('mailing') > 1
          errors.add(:base, "can't have more than one mailing address")
        end
        if !errors.any?# this means that the validation succeeded and we can delete all the persisted ones
          self.office_locations.delete_if{|l| l.persisted?}
        end
      end
    end
    
    def check_legal_name_or_fein_changed?
      fein_changed? || legal_name_changed?
    end
    
  end

  class_methods do
    ENTITY_KINDS = [
      "tax_exempt_organization",
      "c_corporation",
      "s_corporation",
      "partnership",
      "limited_liability_corporation",
      "limited_liability_partnership",
      "household_employer",
      "governmental_employer",
      "foreign_embassy_or_consulate"
    ]

    FIELD_AND_EVENT_NAMES_MAP = {"legal_name" => "name_changed", "fein" => "fein_corrected"}
    
    def generate_fein
      loop do
        random_fein = (["00"] + 7.times.map{rand(10)} ).join
        break random_fein unless Organization.where(:fein => random_fein).count > 0
      end
    end
    
    def search_hash(s_rex)
      search_rex = Regexp.compile(Regexp.escape(s_rex), true)
      {
        "$or" => ([
          {"legal_name" => search_rex},
          {"fein" => search_rex},
        ])
      }
    end
    
    def default_search_order
      [[:legal_name, 1]]
    end
    
    # Expects file_path string with file_name format /hbxid_mmddyyyy_invoices_r.pdf
    # Returns Organization
    def by_invoice_filename(file_path)
      hbx_id= File.basename(file_path).split("_")[0]
      Organization.where(hbx_id: hbx_id).first
    end
  end
end
