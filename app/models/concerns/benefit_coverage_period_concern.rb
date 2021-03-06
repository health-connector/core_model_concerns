require 'active_support/concern'

module BenefitCoveragePeriodConcern
  extend ActiveSupport::Concern

  included do
    include Mongoid::Document
    include Mongoid::Timestamps
    embedded_in :benefit_sponsorship

    # This Benefit Coverage Period's name
    field :title, type: String

    # Market where benefits are available
    field :service_market, type: String

    field :start_on, type: Date
    field :end_on, type: Date
    field :open_enrollment_start_on, type: Date
    field :open_enrollment_end_on, type: Date

    # Second Lowest Cost Silver Plan, by rating area (only one rating area in DC)
    field :slcsp, type: BSON::ObjectId
    field :slcsp_id, type: BSON::ObjectId

    # embeds_many :open_enrollment_periods, class_name: "EnrollmentPeriod"
    embeds_many :benefit_packages

    accepts_nested_attributes_for :benefit_packages

    validates_presence_of :start_on, :end_on, :open_enrollment_start_on, :open_enrollment_end_on, message: "is invalid"

    validates :service_market,
      inclusion: { in: BenefitSponsorship::SERVICE_MARKET_KINDS, message: "%{value} is not a valid service market" }

    validate :end_date_follows_start_date

    before_save :set_title

    scope :by_date, ->(date) { where({:"start_on".lte => date, :"end_on".gte => date}) }

    class << self
      # The HBX benefit coverage period instance for this identifier
      #
      # @param id [ String ] the BSON object identifier
      #
      # @example Which HBX benefit coverage period matches this id?
      #   BenefitCoveragePeriod.find(id)
      #
      # @return [ BenefitCoveragePeriod ] the matching HBX benefit coverage period instance
      def find(id)
        organizations = Organization.where("hbx_profile.benefit_sponsorship.benefit_coverage_periods.id" => BSON::ObjectId.from_string(id))
        organizations.size > 0 ? all.select{ |bcp| bcp.id == id }.first : nil
      end
    end
  end

  class_methods do
    # The HBX benefit coverage period instance that includes this date within its start and end dates
    #
    # @param date [ Date ] the comparison date
    #
    # @example Which HBX benefit coverage period covers this date?
    #   BenefitCoveragePeriod.find_by_date(date)
    #
    # @return [ BenefitCoveragePeriod ] the matching HBX benefit coverage period instance
    def find_by_date(date)
      organizations = Organization.where(
        :"hbx_profile.benefit_sponsorship.benefit_coverage_periods.start_on".lte => date,
        :"hbx_profile.benefit_sponsorship.benefit_coverage_periods.end_on".gte => date)
      if organizations.size > 0
        bcps = organizations.first.hbx_profile.benefit_sponsorship.benefit_coverage_periods
        bcps.select{ |bcp| bcp.start_on <= date && bcp.end_on >= date }.first
      else
        nil
      end
    end

    # All HBX benefit coverage periods
    #
    # @example Which HBX benefit coverage periods are defined?
    #   BenefitCoveragePeriod.all
    #
    # @return [ Array ] the list of HBX benefit coverage periods
    def all
      organizations = Organization.exists(:"hbx_profile.benefit_sponsorship.benefit_coverage_periods" => true)
      organizations.size > 0 ? organizations.first.hbx_profile.benefit_sponsorship.benefit_coverage_periods : nil
    end
  end

  # Sets the earliest coverage effective date
  #
  # @overload start_on=(new_date)
  #
  # @param new_date [ Date ] The earliest coverage effective date
  def start_on=(new_date)
    new_date = Date.parse(new_date) if new_date.is_a? String
    write_attribute(:start_on, new_date.beginning_of_day)
  end

  # Sets the latest date a participant may enroll for coverage
  #
  # @overload end_on=(new_date)
  #
  # @param new_date [ Date ] The latest date a participant may enroll for coverage
  def end_on=(new_date)
    new_date = Date.parse(new_date) if new_date.is_a? String
    write_attribute(:end_on, new_date.end_of_day)
  end

  # Determine if this date is within the benefit coverage period start/end dates
  #
  # @example Is the date within the benefit coverage period?
  #   model.contains?(date)
  #
  # @return [ true, false ] true if the date falls within the period, false if the date is outside the period
  def contains?(date)
    (start_on <= date) && (date <= end_on)
  end

  # Determine if this date is within the open enrollment period start/end dates
  #
  # @param date [ Date ] The comparision date
  #
  # @example Is the date within the open enrollment period?
  #   model.open_enrollment_contains?(date)
  #
  # @return [ true, false ] true if the date falls within the period, false if the date is outside the period
  def open_enrollment_contains?(date)
    (open_enrollment_start_on <= date) && (date <= open_enrollment_end_on)
  end

  # The earliest enrollment termination effective date, based on this date and site settings
  #
  # @param date [ Date ] The comparision date.
  #
  # @example When is the earliest termination effective date?
  #   model.termination_effective_on_for(date)
  #
  # @return [ Date ] the earliest termination effective date.
  def termination_effective_on_for(date)
    if open_enrollment_contains?(date)

      ##  Scendario: Open Enrollment is 11/1 - 1/31
        # 11/3  => 1/1
        # 11/22 => 1/1
        # 12/9  => 1/1
        # 12/23 => 1/31
        #   1/5 => 1/31
        #  1/17 => 2/28

      compare_date = date.end_of_month + 1.day

      return case
      when (compare_date < start_on)  # November
        start_on
      when compare_date == start_on   # December
        if date.day <= HbxProfile::IndividualEnrollmentDueDayOfMonth
          start_on
        else
          start_on.end_of_month
        end
      when compare_date > start_on    # January and forward
        if date.day <= HbxProfile::IndividualEnrollmentDueDayOfMonth
          date.end_of_month
        else
          date.next_month.end_of_month
        end
      end
    else
      dateOfTermMin = TimeKeeper.date_of_record + HbxProfile::IndividualEnrollmentTerminationMinimum
      if (date < dateOfTermMin)
        # If selected date is less than 14 days from today, add 14 days to today's date and that is the termination date.
        effective_date = TimeKeeper.date_of_record + HbxProfile::IndividualEnrollmentTerminationMinimum
      else
        # If selected date is greater than or equal to 14 days from today, the selected date itself is the termination date.
        effective_date = date
      end

      # Add guard to prevent the temination date exceeding end date in the Individual Market
      [effective_date, end_on].min
    end
  end

  # The earliest coverage start effective date, based on today's date and site settings
  #
  # @example When is the earliest coverage start effective date?
  #   model.earliest_effective_date
  #
  # @return [ Date ] the earliest coverage start effective date
  def earliest_effective_date
    if TimeKeeper.date_of_record.day <= HbxProfile::IndividualEnrollmentDueDayOfMonth
      effective_date = TimeKeeper.date_of_record.end_of_month + 1.day
    else
      effective_date = TimeKeeper.date_of_record.next_month.end_of_month + 1.day
    end

    [[effective_date, start_on].max, end_on].min
  end

  private
    def end_date_follows_start_date
      return unless self.end_on.present?
      # Passes validation if end_on == start_date
      errors.add(:end_on, "end_on cannot preceed start_on date") if self.end_on < self.start_on
    end

    def set_title
      return if title.present?
      service_market == "shop" ? market_name = "SHOP" : market_name = "Individual"
      self.title = "#{market_name} Market Benefits #{start_on.year}"
    end
end
