require 'active_support/concern'

module TimeKeeperConcern
  extend ActiveSupport::Concern

  included do |base|
    include Mongoid::Document
    include Singleton
    base::CACHE_KEY = CACHE_KEY

  end

  class_methods do
    CACHE_KEY = "timekeeper/date_of_record"
    def local_time(a_time)
      a_time.in_time_zone("Eastern Time (US & Canada)")
    end

    def date_according_to_exchange_at(a_time)
      a_time.in_time_zone("Eastern Time (US & Canada)").to_date
    end

    # DO NOT EVER USE OUTSIDE OF TESTS
    def set_date_of_record_unprotected!(new_date)
      new_date = new_date.to_date
      if instance.date_of_record != new_date
        (new_date - instance.date_of_record).to_i
        instance.set_date_of_record(new_date)
      end
      instance.date_of_record
    end

    def date_of_record
      instance.date_of_record
    end

    def datetime_of_record
      instant = Time.current
      instance.date_of_record.to_datetime + instant.hour.hours + instant.min.minutes + instant.sec.seconds
    end

    def with_cache
      Thread.current[:time_keeper_local_cached_date] = date_of_record
      yield
      Thread.current[:time_keeper_local_cached_date] = nil
    end
  end

  def push_date_of_record
    BenefitSponsorship.advance_day(self.date_of_record)
  end

  def set_date_of_record(new_date)
    Rails.cache.write(CACHE_KEY, new_date.strftime("%Y-%m-%d"))
  end

  def thread_local_date_of_record
    Thread.current[:time_keeper_local_cached_date]
  end
end
