FactoryBot.define do
  factory :core_person, class: Person do
    first_name 'John'
    sequence(:last_name) {|n| "Smith#{n}" }
    dob "1972-04-04".to_date
    is_incarcerated false
    is_active true
    gender "male"

    after(:create) do |p, evaluator|
      create_list(:address, 2, person: p)
      create_list(:phone, 2, person: p)
      #create_list(:email, 2, person: p)
    end

    trait :with_ssn do
      sequence(:ssn) { |n| 222222220 + n }
    end
  end
end
