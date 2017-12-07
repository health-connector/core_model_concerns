require 'active_support/concern'
require 'securerandom'

module HbxIdGeneratorConcern
  extend ActiveSupport::Concern

  included do |base|
    include Singleton
    attr_accessor :provider

    unless Rails.env.production?
      base.slug!
    end
  end

  class_methods do
    def slug!
      self.instance.provider = SlugSource
    end

    def generate_policy_id
      self.instance.generate_policy_id
    end

    def generate_member_id
      self.instance.generate_member_id
    end

    def generate_organization_id
      self.instance.generate_organization_id
    end
  end

  ## define regular methods here
  def initialize
    @provider = AmqpSource
  end

  def generate_member_id
    provider.generate_member_id
  end

  def generate_policy_id
    provider.generate_policy_id
  end

  def generate_organization_id
    provider.generate_organization_id
  end

  class AmqpSource
    def self.generate_id_from_sequence(sequence_name)
      request_result = nil
      retry_attempt = 0
      while (retry_attempt < 3) && request_result.nil?
        request_result = Acapi::Requestor.request("sequence.next", {:sequence_name => sequence_name}, 2)
        retry_attempt = retry_attempt + 1
      end
      JSON.load(request_result.stringify_keys["body"]).first.to_s
    end

    def self.generate_member_id
      generate_id_from_sequence("member_id")
    end

    def self.generate_policy_id
      generate_id_from_sequence("policy_id")
    end

    def self.generate_organization_id
      generate_id_from_sequence("organization_id")
    end
  end

  class SlugSource
    def self.generate_organization_id
      random_uuid
    end

    def self.generate_policy_id
      random_uuid
    end

    def self.generate_member_id
      random_uuid
    end

    def self.random_uuid
      SecureRandom.uuid.gsub("-","")
    end
  end
end
