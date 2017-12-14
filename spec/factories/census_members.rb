FactoryBot.define do
  factory :census_member do
    first_name "Eddie"
    sequence(:last_name) {|n| "Vedder#{n}" }
    dob "1964-10-23".to_date
    gender "male"
    sequence(:ssn) { |n| 222222220 + n }
    association :address, strategy: :build
    association :email, strategy: :build

    transient do
      create_with_spouse false
    end

    after(:create) do |census_member, evaluator|
      census_member.created_at = TimeKeeper.date_of_record
      if evaluator.create_with_spouse
        census_member.census_dependents << create(:census_member, employee_relationship: 'spouse')
      end
    end
  end

end
