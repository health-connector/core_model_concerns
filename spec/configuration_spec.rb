require 'rails_helper'

RSpec.describe CoreModelConcerns::Configuration do
  describe "#settings" do
    it "returns a Settings object" do
      expect(CoreModelConcerns.configuration.settings).to be_kind_of(Config::Options)
    end
  end

end
