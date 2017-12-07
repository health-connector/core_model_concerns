require 'rails_helper'

describe Person, :dbclean => :around_each do

  describe "model" do
    it { should validate_presence_of :first_name }
    it { should validate_presence_of :last_name }

    let(:first_name) {"Martina"}
    let(:last_name) {"Williams"}
    let(:ssn) {"657637863"}
    let(:gender) {"male"}
    let(:address) {FactoryBot.build(:address)}
    let(:valid_params) do
      { first_name: first_name,
        last_name: last_name,
        ssn: ssn,
        gender: gender,
        addresses: [address]
      }
    end

    describe ".create", dbclean: :around_each do
      context "with valid arguments" do
        let(:params) {valid_params}
        let(:person) {Person.create(**params)}
        before do
          person.valid?
        end

        it 'should generate hbx_id' do
          expect(person.hbx_id).to be_truthy
        end

        context "and a second person is created with the same ssn" do
          let(:person2) {Person.create(**params)}
          before do
            person2.valid?
          end

          context "the second person" do
            it "should not be valid" do
              expect(person2.valid?).to be false
            end

            it "should have an error on ssn" do
              expect(person2.errors[:ssn].any?).to be true
            end

            it "should not have the same id as the first person" do
              expect(person2.id).not_to eq person.id
            end
          end
        end
      end
    end

    describe ".new" do
      context "with no arguments" do
        let(:params) {{}}

        it "should be invalid" do
          expect(Person.new(**params).valid?).to be_falsey
        end
      end

      context "with all valid arguments" do
        let(:params) {valid_params}
        let(:person) {Person.new(**params)}

        it "should save" do
          expect(person.valid?).to be_truthy
        end

        it "should known its relationship is self" do
          expect(person.find_relationship_with(person)).to eq "self"
        end

        it "unread message count is accurate" do
          expect(person.inbox).to be nil
          person.save
          expect(person.inbox.messages.count).to eq 1
          expect(person.inbox.unread_messages.count).to eq 1
        end


      end

      context "with no first_name" do
        let(:params) {valid_params.except(:first_name)}

        it "should fail validation" do
          person = Person.new(**params)
          person.valid?
          expect(person.errors[:first_name].any?).to be_truthy
        end
      end

      context "with no last_name" do
        let(:params) {valid_params.except(:last_name)}

        it "should fail validation" do
          person = Person.new(**params)
          person.valid?
          expect(person.errors[:last_name].any?).to be_truthy
        end
      end

      context "with no ssn" do
        let(:params) {valid_params.except(:ssn)}

        it "should not fail validation" do
          person = Person.new(**params)
          person.valid?
          expect(person.errors[:ssn].any?).to be_falsey
        end
      end

      context "with invalid gender" do
        let(:params) {valid_params.deep_merge({gender: "abc"})}

        it "should fail validation" do
          person = Person.new(**params)
          person.valid?
          expect(person.errors[:gender]).to eq ["abc is not a valid gender"]
        end
      end

      context 'duplicated key issue' do

        def drop_encrypted_ssn_index_in_db
          Person.collection.indexes.each do |spec|
            if spec["key"].keys.include?("encrypted_ssn")
              if spec["unique"] && spec["sparse"]
                Person.collection.indexes.drop_one(spec["key"])
              end
            end
          end
        end

        def create_encrypted_ssn_uniqueness_index
          Person.index_specifications.each do |spec|
            if spec.options[:unique] && spec.options[:sparse]
              if spec.key.keys.include?(:encrypted_ssn)
                key, options = spec.key, spec.options
                Person.collection.indexes.create_one(key, options)
              end
            end
          end
        end

        before :each do
          drop_encrypted_ssn_index_in_db
          create_encrypted_ssn_uniqueness_index
        end

        context "with blank ssn" do

          let(:params) {valid_params.deep_merge({ssn: ""})}

          it "should fail validation" do
            person = Person.new(**params)
            person.valid?
            expect(person.errors[:ssn].any?).to be_falsey
          end

          it "allow duplicated blank ssn" do
            person1 = Person.create(**params)
            person2 = Person.create(**params)
            expect(person2.errors[:ssn].any?).to be_falsey
          end
        end

        context "with nil ssn" do
          let(:params) {valid_params.deep_merge({ssn: nil})}

          it "should fail validation" do
            person = Person.new(**params)
            person.valid?
            expect(person.errors[:ssn].any?).to be_falsey
          end

          it "allow duplicated blank ssn" do
            person1 = Person.create(**params)
            person2 = Person.create(**params)
            expect(person2.errors[:ssn].any?).to be_falsey
          end
        end
      end

      context "with nil ssn" do
        let(:params) {valid_params.deep_merge({ssn: ""})}

        it "should not fail validation" do
          person = Person.new(**params)
          person.valid?
          expect(person.errors[:ssn].any?).to be_falsey
        end
      end

      context "with invalid ssn" do
        let(:params) {valid_params.deep_merge({ssn: "123345"})}

        it "should fail validation" do
          person = Person.new(**params)
          person.valid?
          expect(person.errors[:ssn]).to eq ["SSN must be 9 digits"]
        end
      end

      context "with date of birth" do
        let(:dob){ 25.years.ago }
        let(:params) {valid_params.deep_merge({dob: dob})}

        before(:each) do
          @person = Person.new(**params)
        end

        it "should get the date of birth" do
          expect(@person.date_of_birth).to eq dob.strftime("%m/%d/%Y")
        end

        it "should set the date of birth" do
          @person.date_of_birth = "01/01/1985"
          expect(@person.dob.to_s).to eq "01/01/1985"
        end

        it "should return date of birth as string" do
          expect(@person.dob_to_string).to eq dob.strftime("%Y%m%d")
        end

        it "should return if a person is active or not" do
          expect(@person.is_active?).to eq true
          @person.is_active = false
          expect(@person.is_active?).to eq false
        end

=begin
        context "dob more than 110 years ago" do
          let(:dob){ 200.years.ago }

          it "should have a validation error" do
            expect(@person.valid?).to be_falsey
            expect(@person.errors.full_messages).to include("Dob date cannot be more than 110 years ago")
          end

        end
=end
      end

      context "with invalid date values" do
        context "and date of birth is in future" do
          let(:params) {valid_params.deep_merge({dob: TimeKeeper.date_of_record + 1})}

          it "should fail validation" do
            person = Person.new(**params)
            person.valid?
            expect(person.errors[:dob].size).to eq 1
          end
        end

        context "and date of death is in future" do
          let(:params) {valid_params.deep_merge({date_of_death: TimeKeeper.date_of_record + 1})}

          it "should fail validation" do
            person = Person.new(**params)
            person.valid?
            expect(person.errors[:date_of_death].size).to eq 1
          end
        end

        context "and date of death preceeds date of birth" do
          let(:params) {valid_params.deep_merge({date_of_death: Date.today - 10, dob: Date.today - 1})}

          it "should fail validation" do
            person = Person.new(**params)
            person.valid?
            expect(person.errors[:date_of_death].size).to eq 1
          end
        end
      end
    end
  end

  describe '.match_by_id_info' do
    before(:each) do
      @p0 = Person.create!(first_name: "Jack",   last_name: "Bruce",   dob: "1943-05-14", ssn: "517994321")
      @p1 = Person.create!(first_name: "Ginger", last_name: "Baker",   dob: "1939-08-19", ssn: "888007654")
      @p2 = Person.create!(first_name: "Eric",   last_name: "Clapton", dob: "1945-03-30", ssn: "666332345")
      @p4 = Person.create!(first_name: "Joe",   last_name: "Kramer", dob: "1993-03-30")
    end

#    after(:all) do
#      DatabaseCleaner.clean
#    end

    it 'matches by last_name, first name and dob if no previous ssn and no current ssn' do
      expect(Person.match_by_id_info(last_name: @p4.last_name, dob: @p4.dob, first_name: @p4.first_name)).to eq [@p4]
    end

    it 'matches by last_name, first name and dob if no previous ssn and yes current ssn' do
      expect(Person.match_by_id_info(last_name: @p4.last_name, dob: @p4.dob, first_name: @p4.first_name, ssn: '123123123')).to eq [@p4]
    end

    it 'matches by last_name, first_name and dob if yes previous ssn and no current_ssn' do
      expect(Person.match_by_id_info(last_name: @p0.last_name, dob: @p0.dob, first_name: @p0.first_name)).to eq [@p0]
    end

    it 'matches by last_name, first_name and dob if yes previous ssn and no current_ssn and UPPERCASED' do
      expect(Person.match_by_id_info(last_name: @p0.last_name.upcase, dob: @p0.dob, first_name: @p0.first_name.upcase)).to eq [@p0]
    end

    it 'matches by last_name, first_name and dob if yes previous ssn and no current_ssn and LOWERCASED' do
      expect(Person.match_by_id_info(last_name: @p0.last_name.downcase, dob: @p0.dob, first_name: @p0.first_name.downcase)).to eq [@p0]
    end

    it 'matches by ssn' do
      expect(Person.match_by_id_info(ssn: @p1.ssn)).to eq []
    end

    it 'matches by ssn, last_name and dob' do
      expect(Person.match_by_id_info(last_name: @p2.last_name, dob: @p2.dob, ssn: @p2.ssn)).to eq [@p2]
    end

    it 'not match last_name and dob if not on same record' do
      expect(Person.match_by_id_info(last_name: @p0.last_name, dob: @p1.dob, first_name: @p4.first_name).size).to eq 0
    end

    it 'returns empty array for non-matches' do
      expect(Person.match_by_id_info(ssn: "577600345")).to eq []
    end

    it 'not match last_name and dob if ssn provided (match is already done if ssn ok)' do
      expect(Person.match_by_id_info(last_name: @p0.last_name, dob: @p0.dob, ssn: '999884321').size).to eq 0
    end

    it 'ssn, dob present, then should return person object' do
      expect(Person.match_by_id_info(dob: @p0.dob, ssn: '999884321').size).to eq 0
    end

    it 'ssn present, dob not present then should return empty array' do
      expect(Person.match_by_id_info(ssn: '999884321').size).to eq 0
    end
  end

  describe '.active', :dbclean => :around_each do
    it 'new person defaults to is_active' do
      expect(Person.create!(first_name: "eric", last_name: "Clapton").is_active).to eq true
    end

    it 'returns person records only where is_active == true' do
      p1 = Person.create!(first_name: "Jack", last_name: "Bruce", is_active: false)
      p2 = Person.create!(first_name: "Ginger", last_name: "Baker")
      expect(Person.active.size).to eq 1
      expect(Person.active.first).to eq p2
    end
  end

  ## Instance methods
  describe '#addresses' do
    it "invalid address bubbles up" do
      person = Person.new
      addresses = person.addresses.build({address_1: "441 4th ST, NW", city: "Washington", state: "DC", zip: "20001"})
      expect(person.valid?).to eq false
      expect(person.errors[:addresses].any?).to eq true
    end

    it 'persists associated address', dbclean: :after_each do
      # setup
      person = FactoryBot.build(:core_person)
      addresses = person.addresses.build({kind: "home", address_1: "441 4th ST, NW", city: "Washington", state: "DC", zip: "20001"})

      result = person.save

      expect(result).to eq true
      expect(person.addresses.first.kind).to eq "home"
      expect(person.addresses.first.city).to eq "Washington"
    end
  end

  describe '#person_relationships' do
    it 'accepts associated addresses' do
      # setup
      person = FactoryBot.build(:core_person)
      relationship = person.person_relationships.build({kind: "self", relative: person})

      expect(person.save).to eq true
      expect(person.person_relationships.size).to eq 1
      expect(relationship.invert_relationship.kind).to eq "self"
    end
  end

  describe '#full_name' do
    it 'returns the concatenated name attributes' do
      expect(Person.new(first_name: "Ginger", last_name: "Baker").full_name).to eq 'Ginger Baker'
    end
  end

  describe '#phones' do
    it "sets person's home telephone number" do
      person = Person.new
      person.phones.build({kind: 'home', area_code: '202', number: '555-1212'})

      # expect(person.phones.first.number).to eq '5551212'
    end
  end

  describe "does not allow two people with the same user ID to be saved" do
    let(:person1){FactoryBot.build(:core_person)}
    let(:person2){FactoryBot.build(:core_person)}
        def drop_user_id_index_in_db
          Person.collection.indexes.each do |spec|
            if spec["key"].keys.include?("user_id")
              if spec["unique"] && spec["sparse"]
                Person.collection.indexes.drop_one(spec["key"])
              end
            end
          end
        end

        def create_user_id_uniqueness_index
          Person.index_specifications.each do |spec|
            if spec.options[:unique] && spec.options[:sparse]
              if spec.key.keys.include?(:user_id)
                key, options = spec.key, spec.options
                Person.collection.indexes.create_one(key, options)
              end
            end
          end
        end

        before :each do
          drop_user_id_index_in_db
          create_user_id_uniqueness_index
        end

    it "should let fail to save" do
      user_id = BSON::ObjectId.new
      person1.user_id = user_id
      person2.user_id = user_id
      person1.save!
      expect { person2.save! }.to raise_error(Mongo::Error::OperationFailure)
    end

  end


  describe "validation of date_of_birth and date_of_death" do
    let(:person) { FactoryBot.create(:core_person) }

    context "validate of date_of_birth_is_past" do
      it "should invalid" do
        dob = (Date.today + 10.days)
        allow(person).to receive(:dob).and_return(dob)
        expect(person.save).to be_falsey
        expect(person.errors[:dob].any?).to be_truthy
        expect(person.errors[:dob].to_s).to match /future date: #{dob.to_s} is invalid date of birth/
      end
    end

    context "date_of_death_is_blank_or_past" do
      it "should invalid" do
        date_of_death = (Date.today + 10.days)
        allow(person).to receive(:date_of_death).and_return(date_of_death)
        expect(person.save).to be_falsey
        expect(person.errors[:date_of_death].any?).to be_truthy
        expect(person.errors[:date_of_death].to_s).to match /future date: #{date_of_death.to_s} is invalid date of death/
      end
    end
  end

  describe "us_citizen status" do
    let(:person) { FactoryBot.create(:core_person) }

    before do
      person.us_citizen="false"
    end

    context "set to false" do
      it "should set @us_citizen to false" do
        expect(person.us_citizen).to be_falsey
      end

      it "should set @naturalized_citizen to false" do
        expect(person.naturalized_citizen).to be_falsey
      end
    end
  end

  describe "residency_eligible?" do
    let(:person) { FactoryBot.create(:core_person) }

    it "should false" do
      person.no_dc_address = false
      person.no_dc_address_reason = ""
      expect(person.residency_eligible?).to be_falsey
    end

    it "should false" do
      person.no_dc_address = true
      person.no_dc_address_reason = ""
      expect(person.residency_eligible?).to be_falsey
    end

    it "should true" do
      person.no_dc_address = true
      person.no_dc_address_reason = "I am Homeless"
      expect(person.residency_eligible?).to be_truthy
    end
  end

  describe "home_address" do
    let(:person) { FactoryBot.create(:core_person) }

    it "return home address" do
      address_1 = Address.new(kind: 'home')
      address_2 = Address.new(kind: 'mailing')
      allow(person).to receive(:addresses).and_return [address_1, address_2]

      expect(person.home_address).to eq address_1
    end
  end

  describe "is_dc_resident?" do
    context "when no_dc_address is true" do
      let(:person) { Person.new(no_dc_address: true) }

      it "return false with no_dc_address_reason" do
        allow(person).to receive(:no_dc_address_reason).and_return "reason"
        expect(person.is_dc_resident?).to eq true
      end

      it "return true without no_dc_address_reason" do
        allow(person).to receive(:no_dc_address_reason).and_return ""
        expect(person.is_dc_resident?).to eq false
      end
    end

    context "when no_dc_address is false" do
      let(:person) { Person.new(no_dc_address: false) }

      context "when state is not dc" do
        let(:home_addr) {Address.new(kind: 'home', state: 'AC')}
        let(:mailing_addr) {Address.new(kind: 'mailing', state: 'AC')}
        let(:work_addr) { Address.new(kind: 'work', state: 'AC') }
        it "home" do
          allow(person).to receive(:addresses).and_return [home_addr]
          expect(person.is_dc_resident?).to eq false
        end

        it "mailing" do
          allow(person).to receive(:addresses).and_return [mailing_addr]
          expect(person.is_dc_resident?).to eq false
        end

        it "work" do
          allow(person).to receive(:addresses).and_return [work_addr]
          expect(person.is_dc_resident?).to eq false
        end
      end

      context "when state is in settings state" do
        let(:home_addr) {Address.new(kind: 'home', state: Settings.aca.state_abbreviation)}
        let(:mailing_addr) {Address.new(kind: 'mailing', state: Settings.aca.state_abbreviation)}
        let(:work_addr) { Address.new(kind: 'work', state: Settings.aca.state_abbreviation) }
        it "home" do
          allow(person).to receive(:addresses).and_return [home_addr]
          expect(person.is_dc_resident?).to eq true
        end

        it "mailing" do
          allow(person).to receive(:addresses).and_return [mailing_addr]
          expect(person.is_dc_resident?).to eq true
        end

        it "work" do
          allow(person).to receive(:addresses).and_return [work_addr]
          expect(person.is_dc_resident?).to eq false
        end
      end
    end
  end
end
