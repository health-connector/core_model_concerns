require 'active_support/concern'

module BenefitSponsorshipConcern
  extend ActiveSupport::Concern

  included do
    include Mongoid::Document
    include Mongoid::Timestamps

    field :service_markets, type: Array, default: []

    embedded_in :hbx_profile

    # 2015, 2016, etc. (aka plan_year)
    embeds_many :benefit_coverage_periods
    embeds_many :geographic_rating_areas

    accepts_nested_attributes_for :benefit_coverage_periods, :geographic_rating_areas

    validates_presence_of :service_markets

    class << self
      def find(id)
        orgs = Organization.where("hbx_profile.benefit_sponsorship._id" => BSON::ObjectId.from_string(id))
        orgs.size > 0 ? orgs.first.hbx_profile.benefit_sponsorship : nil
      end
    end
  end

  class_methods do
    SERVICE_MARKET_KINDS = %w(shop individual coverall)

    def advance_day(new_date)

      hbx_sponsors = Organization.exists("hbx_profile.benefit_sponsorship": true).reduce([]) { |memo, org| memo << org.hbx_profile }

      hbx_sponsors.each do |hbx_sponsor|
        hbx_sponsor.advance_day
        hbx_sponsor.advance_month   if new_date.day == 1
        hbx_sponsor.advance_quarter if new_date.day == 1 && [1, 4, 7, 10].include?(new_date.month)
        hbx_sponsor.advance_year    if new_date.day == 1 && new_date.month == 1
      end
    end
  end

  def current_benefit_coverage_period
    benefit_coverage_periods.detect { |bcp| bcp.contains?(TimeKeeper.date_of_record) }
  end

  def renewal_benefit_coverage_period
    benefit_coverage_periods.detect { |bcp| bcp.contains?(TimeKeeper.date_of_record + 1.year) }
  end

  def earliest_effective_date
    current_benefit_period.earliest_effective_date if current_benefit_period
  end

  def benefit_coverage_period_by_effective_date(effective_date)
    benefit_coverage_periods.detect { |bcp| bcp.contains?(effective_date) }
  end

  # def is_under_special_enrollment_period?
  #   benefit_coverage_periods.detect { |bcp| bcp.contains?(TimeKeeper.date_of_record) }
  # end

  def is_under_open_enrollment?
    benefit_coverage_periods.any? do |benefit_coverage_period|
      benefit_coverage_period.open_enrollment_contains?(TimeKeeper.date_of_record)
    end
  end

  def current_benefit_period
    if renewal_benefit_coverage_period && renewal_benefit_coverage_period.open_enrollment_contains?(TimeKeeper.date_of_record)
      renewal_benefit_coverage_period
    else
      current_benefit_coverage_period
    end
  end
end
