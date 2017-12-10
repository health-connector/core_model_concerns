require 'rails_helper'

RSpec.describe CensusMember, :dbclean => :around_each do
  it { should validate_presence_of :first_name }
  it { should validate_presence_of :last_name }
  it { should validate_presence_of :dob }

  let(:census_member) { FactoryBot.create(:census_member) }

  it "sets gender" do
    census_member.gender = "MALE"
    expect(census_member.gender).to eq "male"
  end

  it "sets date of birth" do
    census_member.date_of_birth = "1980-12-12"
    expect(census_member.dob).to eq "1980-12-12".to_date
  end

  context "dob" do
    before(:each) do
      census_member.date_of_birth = "1980-12-01"
    end

    it "dob_string" do
      expect(census_member.dob_string).to eq "19801201"
    end

    it "date_of_birth" do
      expect(census_member.date_of_birth).to eq "12/01/1980"
    end

    context "dob more than 110 years ago" do
      before(:each) do
        census_member.dob = 111.years.ago
      end

      it "generate validation error" do
        expect(census_member.valid?).to be_falsey
        expect(census_member.errors.full_messages).to include("Dob date cannot be more than 110 years ago")
      end
    end
  end

  context "validate of date_of_birth_is_past" do
    it "should invalid" do
      dob = (Date.today + 10.days)
      census_member.date_of_birth = dob.strftime("%Y-%m-%d")
      expect(census_member.save).to be_falsey
      expect(census_member.errors[:dob].any?).to be_truthy
      expect(census_member.errors[:dob].to_s).to match /future date: #{dob.to_s} is invalid date of birth/
    end
  end

  context "without a gender" do
    it "should be invalid" do
      expect(census_member.valid?).to eq true
      census_member.gender = nil
      expect(census_member.valid?).to eq false
      expect(census_member.errors[:gender].to_s).to match(/must be selected/)
    end
  end
end
