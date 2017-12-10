FactoryBot.define do
  factory :census_member do
    first_name "Eddie"
    sequence(:last_name) {|n| "Vedder#{n}" }
    dob "1964-10-23".to_date
    gender "male"
    association :address, strategy: :build
    association :email, strategy: :build
  end

end
