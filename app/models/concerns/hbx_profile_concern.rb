require 'active_support/concern'

module HbxProfileConcern
  extend ActiveSupport::Concern

  included do
    include Mongoid::Document
    include Mongoid::Timestamps
    include ConfigAcaLocationConcern

    field :cms_id, type: String
    field :us_state_abbreviation, type: String

    delegate :legal_name, :legal_name=, to: :organization, allow_nil: true
    delegate :dba, :dba=, to: :organization, allow_nil: true
    delegate :fein, :fein=, to: :organization, allow_nil: true
    delegate :entity_kind, :entity_kind=, to: :organization, allow_nil: true


    embeds_one :benefit_sponsorship, cascade_callbacks: true
    embeds_one :inbox, as: :recipient, cascade_callbacks: true

    accepts_nested_attributes_for :inbox, :benefit_sponsorship

    validates_presence_of :us_state_abbreviation, :cms_id

    after_initialize :build_nested_models

    class << self
      def find(id)
        org = Organization.where("hbx_profile._id" => BSON::ObjectId.from_string(id)).first
        org.hbx_profile if org.present?
      end
      def find_by_cms_id(id)
        org = Organization.where("hbx_profile.cms_id": id).first
        org.hbx_profile if org.present?
      end

      def find_by_state_abbreviation(state)
        org = Organization.where("hbx_profile.us_state_abbreviation": state.to_s.upcase).first
        org.hbx_profile if org.present?
      end

      def all
        Organization.exists(hbx_profile: true).all.reduce([]) { |set, org| set << org.hbx_profile }
      end
    end
  end

  class_methods do

  end

  def advance_day
  end

  def advance_month
  end

  def advance_quarter
  end

  def advance_year
  end

  def under_open_enrollment?
    (benefit_sponsorship.present? && benefit_sponsorship.is_under_open_enrollment?) ?  true : false
  end

  private
    def build_nested_models
      build_inbox if inbox.nil?
    end

    def save_inbox
      welcome_subject = "Welcome to #{site_short_name}"
      welcome_body = "#{site_short_name} is the #{aca_state_name}'s on-line marketplace to shop, compare, and select health insurance that meets your health needs and budgets."
      @inbox.save
      @inbox.messages.create(subject: welcome_subject, body: welcome_body)
    end
end
