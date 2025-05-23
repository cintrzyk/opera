# Opera

[![Gem Version](https://badge.fury.io/rb/opera.svg)](https://badge.fury.io/rb/opera)
![Master](https://github.com/Profinda/opera/actions/workflows/release.yml/badge.svg?branch=master)


Simple DSL for services/interactions classes.

Opera was born to mimic some of the philosophy of the dry gems but keeping the DSL simple.

Our aim was and is to write as many Operations, Services and Interactions using this fun and intuitive DSL to help developers have consistent code, easy to understand and maintain.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'opera'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install opera

Note. If you are using Ruby 2.x please use Opera 0.2.x

## Configuration

Opera is built to be used with or without Rails.
Simply initialize the configuration and choose a custom logger and which library to use for implementing transactions.

```ruby
Opera::Operation::Config.configure do |config|
  config.transaction_class = ActiveRecord::Base
  config.transaction_method = :transaction
  config.transaction_options = { requires_new: true, level: :step } # or level: :operation - default
  config.instrumentation_class = Datadog::Tracing
  config.instrumentation_method = :trace
  config.instrumentation_options = { service: :operation }
  config.mode = :development # Can be set to production too
  config.reporter = defined?(Rollbar) ? Rollbar : Rails.logger
end
```

You can later override this configuration in each Operation to have more granularity


## Usage

Once opera gem is in your project you can start to build Operations

```ruby
class A < Opera::Operation::Base
  configure do |config|
    config.transaction_class = Profile
    config.reporter = Rails.logger
  end

  success :populate

  operation :inner_operation

  validate :profile_schema

  transaction do
    step :create
    step :update
    step :destroy
  end

  validate do
    step :validate_object
    step :validate_relationships
  end

  benchmark do
    success :hal_sync
  end

  success do
    step :send_mail
    step :report_to_audit_log
  end

  step :output
end
```

Start developing your business logic, services and interactions as Opera::Operations and benefit of code that is documented, self-explanatory, easy to maintain and debug.


### Specs

When using Opera::Operation inside an engine add the following
configuration to your spec_helper.rb or rails_helper.rb:

```ruby
Opera::Operation::Config.configure do |config|
  config.transaction_class = ActiveRecord::Base
end
```

Without this extra configuration you will receive:
```ruby
NoMethodError:
  undefined method `transaction' for nil:NilClass
```

### Instrumentation

When you want to easily instrument your operations you can add this to the opera config:

```ruby
Rails.application.configure do
  config.x.instrumentation_class = Datadog::Tracing
  config.x.instrumentation_method = :trace
  config.x.instrumentation_options = { service: :opera }
end
```

You can also instrument individual operations by adding this to the operation config:

```ruby
class A < Opera::Operation::Base
  configure do |config|
    config.instrumentation_class = Datadog::Tracing
    config.instrumentation_method = :trace
    config.instrumentation_options = { service: :opera, level: :step }
  end

  # steps
end
```

### Content
[Basic operation](#user-content-basic-operation)

[Example with sanitizing parameters](#user-content-example-with-sanitizing-parameters)

[Example operation with old validations](#user-content-example-operation-with-old-validations)

[Failing transaction](#user-content-failing-transaction)

[Passing transaction](#user-content-passing-transaction)

[Benchmark](#user-content-benchmark)

[Success](#user-content-success)

[Finish if](#user-content-finish-if)

[Inner Operation](#user-content-inner-operation)

[Inner Operations](#user-content-inner-operations)

## Usage examples

Some cases and example how to use new operations

### Basic operation

```ruby
class Profile::Create < Opera::Operation::Base
  # DEPRECATED
  # context_accessor :profile
  context do
    attr_accessor :profile
  end
  # DEPRECATED
  # dependencies_reader :current_account, :mailer
  dependencies do
    attr_reader :current_account, :mailer
  end

  validate :profile_schema

  step :create
  step :send_email
  step :output

  def profile_schema
    Dry::Validation.Schema do
      required(:first_name).filled
    end.call(params)
  end

  def create
    self.profile = current_account.profiles.create(params)
  end

  def send_email
    mailer&.send_mail(profile: profile)
  end

  def output
    result.output = { model: profile }
  end
end
```

#### Call with valid parameters

```ruby
Profile::Create.call(params: {
  first_name: :foo,
  last_name: :bar
}, dependencies: {
  mailer: MyMailer,
  current_account: Account.find(1)
})

#<Opera::Operation::Result:0x0000561636dced60 @errors={}, @information={}, @executions=[:profile_schema, :create, :send_email, :output], @output={:model=>#<Profile id: 30, user_id: nil, linkedin_uid: nil, picture: nil, headline: nil, summary: nil, first_name: "foo", last_name: "bar", created_at: "2020-08-14 16:04:08", updated_at: "2020-08-14 16:04:08", agree_to_terms_and_conditions: nil, registration_status: "", account_id: 1, start_date: nil, supervisor_id: nil, picture_processing: false, statistics: {}, data: {}, notification_timestamps: {}, suggestions: {}, notification_settings: {}, contact_information: []>}>
```

#### Call with INVALID parameters - missing first_name

```ruby
Profile::Create.call(params: {
  last_name: :bar
}, dependencies: {
  mailer: MyMailer,
  current_account: Account.find(1)
})

#<Opera::Operation::Result:0x0000562d3f635390 @errors={:first_name=>["is missing"]}, @information={}, @executions=[:profile_schema]>
```

#### Call with MISSING dependencies

```ruby
Profile::Create.call(params: {
  first_name: :foo,
  last_name: :bar
}, dependencies: {
  current_account: Account.find(1)
})

#<Opera::Operation::Result:0x007f87ba2c8f00 @errors={}, @information={}, @executions=[:profile_schema, :create, :send_email, :output], @output={:model=>#<Profile id: 33, user_id: nil, linkedin_uid: nil, picture: nil, headline: nil, summary: nil, first_name: "foo", last_name: "bar", created_at: "2019-01-03 12:04:25", updated_at: "2019-01-03 12:04:25", agree_to_terms_and_conditions: nil, registration_status: "", account_id: 1, start_date: nil, supervisor_id: nil, picture_processing: false, statistics: {}, data: {}, notification_timestamps: {}, suggestions: {}, notification_settings: {}, contact_information: []>}>
```

### Example with sanitizing parameters

```ruby
class Profile::Create < Opera::Operation::Base
  # DEPRECATED
  # context_accessor :profile
  context do
    attr_accessor :profile
  end
  # DEPRECATED
  # dependencies_reader :current_account, :mailer
  dependencies do
    attr_reader :current_account, :mailer
  end


  validate :profile_schema

  step :create
  step :send_email
  step :output

  def profile_schema
    Dry::Validation.Schema do
      configure { config.input_processor = :sanitizer }

      required(:first_name).filled
    end.call(params)
  end

  def create
    self.profile = current_account.profiles.create(context[:profile_schema_output])
  end

  def send_email
    return true unless mailer

    mailer.send_mail(profile: profile)
  end

  def output
    result.output = { model: profile }
  end
end
```

```ruby
Profile::Create.call(params: {
  first_name: :foo,
  last_name: :bar
}, dependencies: {
  mailer: MyMailer,
  current_account: Account.find(1)
})

# NOTE: Last name is missing in output model
#<Opera::Operation::Result:0x000055e36a1fab78 @errors={}, @information={}, @executions=[:profile_schema, :create, :send_email, :output], @output={:model=>#<Profile id: 44, user_id: nil, linkedin_uid: nil, picture: nil, headline: nil, summary: nil, first_name: "foo", last_name: nil, created_at: "2020-08-17 11:07:08", updated_at: "2020-08-17 11:07:08", agree_to_terms_and_conditions: nil, registration_status: "", account_id: 1, start_date: nil, supervisor_id: nil, picture_processing: false, statistics: {}, data: {}, notification_timestamps: {}, suggestions: {}, notification_settings: {}, contact_information: []>}>
```

### Example operation with old validations

```ruby
class Profile::Create < Opera::Operation::Base
  # DEPRECATED
  # context_accessor :profile
  context do
    attr_accessor :profile
  end
  # DEPRECATED
  # dependencies_reader :current_account, :mailer
  dependencies do
    attr_reader :current_account, :mailer
  end

  validate :profile_schema

  step :build_record
  step :old_validation
  step :create
  step :send_email
  step :output

  def profile_schema
    Dry::Validation.Schema do
      required(:first_name).filled
    end.call(params)
  end

  def build_record
    self.profile = current_account.profiles.build(params)
    self.profile.force_name_validation = true
  end

  def old_validation
    return true if profile.valid?

    result.add_information(missing_validations: "Please check dry validations")
    result.add_errors(profile.errors.messages)

    false
  end

  def create
    profile.save
  end

  def send_email
    mailer.send_mail(profile: profile)
  end

  def output
    result.output = { model: profile }
  end
end
```

#### Call with valid parameters

```ruby
Profile::Create.call(params: {
  first_name: :foo,
  last_name: :bar
}, dependencies: {
  mailer: MyMailer,
  current_account: Account.find(1)
})

#<Opera::Operation::Result:0x0000560ebc9e7a98 @errors={}, @information={}, @executions=[:profile_schema, :build_record, :old_validation, :create, :send_email, :output], @output={:model=>#<Profile id: 41, user_id: nil, linkedin_uid: nil, picture: nil, headline: nil, summary: nil, first_name: "foo", last_name: "bar", created_at: "2020-08-14 19:15:12", updated_at: "2020-08-14 19:15:12", agree_to_terms_and_conditions: nil, registration_status: "", account_id: 1, start_date: nil, supervisor_id: nil, picture_processing: false, statistics: {}, data: {}, notification_timestamps: {}, suggestions: {}, notification_settings: {}, contact_information: []>}>
```

#### Call with INVALID parameters

```ruby
Profile::Create.call(params: {
  first_name: :foo
}, dependencies: {
  mailer: MyMailer,
  current_account: Account.find(1)
})

#<Opera::Operation::Result:0x0000560ef76ba588 @errors={:last_name=>["can't be blank"]}, @information={:missing_validations=>"Please check dry validations"}, @executions=[:build_record, :old_validation]>
```

### Example with step that finishes execution

```ruby
class Profile::Create < Opera::Operation::Base
  # DEPRECATED
  # context_accessor :profile
  context do
    attr_accessor :profile
  end
  # DEPRECATED
  # dependencies_reader :current_account, :mailer
  dependencies do
    attr_reader :current_account, :mailer
  end

  validate :profile_schema

  step :build_record
  step :create
  step :send_email
  step :output

  def profile_schema
    Dry::Validation.Schema do
      required(:first_name).filled
    end.call(params)
  end

  def build_record
    self.profile = current_account.profiles.build(params)
    self.profile.force_name_validation = true
  end

  def create
    self.profile = profile.save
    finish!
  end

  def send_email
    return true unless mailer

    mailer.send_mail(profile: profile)
  end

  def output
    result.output(model: profile)
  end
end
```

##### Call

```ruby
result = Profile::Create.call(params: {
  first_name: :foo,
  last_name: :bar
}, dependencies: {
  current_account: Account.find(1)
})

#<Opera::Operation::Result:0x007fc2c59a8460 @errors={}, @information={}, @executions=[:profile_schema, :build_record, :create]>
```

### Failing transaction

```ruby
class Profile::Create < Opera::Operation::Base
  configure do |config|
    config.transaction_class = Profile
  end

  # DEPRECATED
  # context_accessor :profile
  context do
    attr_accessor :profile
  end
  # DEPRECATED
  # dependencies_reader :current_account, :mailer
  dependencies do
    attr_reader :current_account, :mailer
  end

  validate :profile_schema

  transaction do
    step :create
    step :update
  end

  step :send_email
  step :output

  def profile_schema
    Dry::Validation.Schema do
      required(:first_name).filled
    end.call(params)
  end

  def create
    self.profile = current_account.profiles.create(params)
  end

  def update
    profile.update(example_attr: :Example)
  end

  def send_email
    return true unless mailer

    mailer.send_mail(profile: profile)
  end

  def output
    result.output = { model: profile }
  end
end
```

#### Example with non-existing attribute

```ruby
Profile::Create.call(params: {
  first_name: :foo,
  last_name: :bar
}, dependencies: {
  mailer: MyMailer,
  current_account: Account.find(1)
})

D, [2020-08-14T16:13:30.946466 #2504] DEBUG -- :   Account Load (0.5ms)  SELECT  "accounts".* FROM "accounts" WHERE "accounts"."deleted_at" IS NULL AND "accounts"."id" = $1 LIMIT $2  [["id", 1], ["LIMIT", 1]]
D, [2020-08-14T16:13:30.960254 #2504] DEBUG -- :    (0.2ms)  BEGIN
D, [2020-08-14T16:13:30.983981 #2504] DEBUG -- :   SQL (0.7ms)  INSERT INTO "profiles" ("first_name", "last_name", "created_at", "updated_at", "account_id") VALUES ($1, $2, $3, $4, $5) RETURNING "id"  [["first_name", "foo"], ["last_name", "bar"], ["created_at", "2020-08-14 16:13:30.982289"], ["updated_at", "2020-08-14 16:13:30.982289"], ["account_id", 1]]
D, [2020-08-14T16:13:30.986233 #2504] DEBUG -- :    (0.2ms)  ROLLBACK
D, [2020-08-14T16:13:30.988231 #2504] DEBUG -- :    unknown attribute 'example_attr' for Profile. (ActiveModel::UnknownAttributeError)
```

### Passing transaction

```ruby
class Profile::Create < Opera::Operation::Base
  configure do |config|
    config.transaction_class = Profile
  end

  # DEPRECATED
  # context_accessor :profile
  context do
    attr_accessor :profile
  end
  # DEPRECATED
  # dependencies_reader :current_account, :mailer
  dependencies do
    attr_reader :current_account, :mailer
  end

  validate :profile_schema

  transaction do
    step :create
    step :update
  end

  step :send_email
  step :output

  def profile_schema
    Dry::Validation.Schema do
      required(:first_name).filled
    end.call(params)
  end

  def create
    self.profile = current_account.profiles.create(params)
  end

  def update
    profile.update(updated_at: 1.day.ago)
  end

  def send_email
    return true unless mailer

    mailer.send_mail(profile: profile)
  end

  def output
    result.output = { model: profile }
  end
end
```

#### Example with updating timestamp

```ruby
Profile::Create.call(params: {
  first_name: :foo,
  last_name: :bar
}, dependencies: {
  mailer: MyMailer,
  current_account: Account.find(1)
})
D, [2020-08-17T12:10:44.842392 #2741] DEBUG -- :   Account Load (0.7ms)  SELECT  "accounts".* FROM "accounts" WHERE "accounts"."deleted_at" IS NULL AND "accounts"."id" = $1 LIMIT $2  [["id", 1], ["LIMIT", 1]]
D, [2020-08-17T12:10:44.856964 #2741] DEBUG -- :    (0.2ms)  BEGIN
D, [2020-08-17T12:10:44.881332 #2741] DEBUG -- :   SQL (0.7ms)  INSERT INTO "profiles" ("first_name", "last_name", "created_at", "updated_at", "account_id") VALUES ($1, $2, $3, $4, $5) RETURNING "id"  [["first_name", "foo"], ["last_name", "bar"], ["created_at", "2020-08-17 12:10:44.879684"], ["updated_at", "2020-08-17 12:10:44.879684"], ["account_id", 1]]
D, [2020-08-17T12:10:44.886168 #2741] DEBUG -- :   SQL (0.6ms)  UPDATE "profiles" SET "updated_at" = $1 WHERE "profiles"."id" = $2  [["updated_at", "2020-08-16 12:10:44.883164"], ["id", 47]]
D, [2020-08-17T12:10:44.898132 #2741] DEBUG -- :    (10.3ms)  COMMIT
#<Opera::Operation::Result:0x0000556528f29058 @errors={}, @information={}, @executions=[:profile_schema, :create, :update, :send_email, :output], @output={:model=>#<Profile id: 47, user_id: nil, linkedin_uid: nil, picture: nil, headline: nil, summary: nil, first_name: "foo", last_name: "bar", created_at: "2020-08-17 12:10:44", updated_at: "2020-08-16 12:10:44", agree_to_terms_and_conditions: nil, registration_status: "", account_id: 1, start_date: nil, supervisor_id: nil, picture_processing: false, statistics: {}, data: {}, notification_timestamps: {}, suggestions: {}, notification_settings: {}, contact_information: []>}>
```

### Benchmark

```ruby
class Profile::Create < Opera::Operation::Base
  # DEPRECATED
  # context_accessor :profile
  context do
    attr_accessor :profile
  end
  # DEPRECATED
  # dependencies_reader :current_account, :mailer
  dependencies do
    attr_reader :current_account, :mailer
  end

  validate :profile_schema

  benchmark :fast_section do
    step :create
    step :update
  end

  benchmark :slow_section do
    step :send_email
    step :output
  end

  def profile_schema
    Dry::Validation.Schema do
      required(:first_name).filled
    end.call(params)
  end

  def create
    self.profile = current_account.profiles.create(params)
  end

  def update
    profile.update(updated_at: 1.day.ago)
  end

  def send_email
    return true unless mailer

    mailer.send_mail(profile: profile)
  end

  def output
    result.output = { model: profile }
  end
end
```

#### Example with information (real and total) from benchmark

```ruby
Profile::Create.call(params: {
  first_name: :foo,
  last_name: :bar
}, dependencies: {
  current_account: Account.find(1)
})
#<Opera::Operation::Result:0x007ff414a01238 @errors={}, @information={fast_section: {:real=>0.300013706088066e-05, :total=>0.0}, slow_section: {:real=>1.800013706088066e-05, :total=>0.0}}, @executions=[:profile_schema, :create, :update, :send_email, :output], @output={:model=>#<Profile id: 30, user_id: nil, linkedin_uid: nil, picture: nil, headline: nil, summary: nil, first_name: "foo", last_name: "bar", created_at: "2020-08-19 10:46:00", updated_at: "2020-08-18 10:46:00", agree_to_terms_and_conditions: nil, registration_status: "", account_id: 1, start_date: nil, supervisor_id: nil, picture_processing: false, statistics: {}, data: {}, notification_timestamps: {}, suggestions: {}, notification_settings: {}, contact_information: []>}>
```

### Success

```ruby
class Profile::Create < Opera::Operation::Base
  # DEPRECATED
  # context_accessor :profile
  context do
    attr_accessor :profile
  end
  # DEPRECATED
  # dependencies_reader :current_account, :mailer
  dependencies do
    attr_reader :current_account, :mailer
  end

  validate :profile_schema

  success :populate

  step :create
  step :update

  success do
    step :send_email
    step :output
  end

  def profile_schema
    Dry::Validation.Schema do
      required(:first_name).filled
    end.call(params)
  end

  def populate
    context[:attributes] = {}
    context[:valid] = false
  end

  def create
    self.profile = current_account.profiles.create(params)
  end

  def update
    profile.update(updated_at: 1.day.ago)
  end

  # NOTE: We can add an error in this step and it won't break the execution
  def send_email
    result.add_error('mailer', 'Missing dependency')
    mailer&.send_mail(profile: profile)
  end

  def output
    result.output = { model: context[:profile] }
  end
end
```

#### Example output for success block

```ruby
Profile::Create.call(params: {
  first_name: :foo,
  last_name: :bar
}, dependencies: {
  current_account: Account.find(1)
})
#<Opera::Operation::Result:0x007fd0248e5638 @errors={"mailer"=>["Missing dependency"]}, @information={}, @executions=[:profile_schema, :populate, :create, :update, :send_email, :output], @output={:model=>#<Profile id: 40, user_id: nil, linkedin_uid: nil, picture: nil, headline: nil, summary: nil, first_name: "foo", last_name: "bar", created_at: "2019-01-03 12:21:35", updated_at: "2019-01-02 12:21:35", agree_to_terms_and_conditions: nil, registration_status: "", account_id: 1, start_date: nil, supervisor_id: nil, picture_processing: false, statistics: {}, data: {}, notification_timestamps: {}, suggestions: {}, notification_settings: {}, contact_information: []>}>
```

### Finish If

```ruby
class Profile::Create < Opera::Operation::Base
  # DEPRECATED
  # context_accessor :profile
  context do
    attr_accessor :profile
  end
  # DEPRECATED
  # dependencies_reader :current_account, :mailer
  dependencies do
    attr_reader :current_account, :mailer
  end

  validate :profile_schema

  step :create
  finish_if :profile_create_only
  step :update

  success do
    step :send_email
    step :output
  end

  def profile_schema
    Dry::Validation.Schema do
      required(:first_name).filled
    end.call(params)
  end

  def create
    self.profile = current_account.profiles.create(params)
  end

  def profile_create_only
    dependencies[:create_only].present?
  end

  def update
    profile.update(updated_at: 1.day.ago)
  end

  # NOTE: We can add an error in this step and it won't break the execution
  def send_email
    result.add_error('mailer', 'Missing dependency')
    mailer&.send_mail(profile: profile)
  end

  def output
    result.output = { model: context[:profile] }
  end
end
```

#### Example with information (real and total) from benchmark

```ruby
Profile::Create.call(params: {
  first_name: :foo,
  last_name: :bar
}, dependencies: {
  create_only: true,
  current_account: Account.find(1)
})
#<Opera::Operation::Result:0x007fd0248e5638 @errors={}, @information={}, @executions=[:profile_schema, :create, :profile_create_only], @output={}>
```

### Inner Operation

```ruby
class Profile::Find < Opera::Operation::Base
  step :find

  def find
    result.output = Profile.find(params[:id])
  end
end

class Profile::Create < Opera::Operation::Base
  validate :profile_schema

  operation :find

  step :create

  step :output

  def profile_schema
    Dry::Validation.Schema do
      optional(:id).filled
    end.call(params)
  end

  def find
    Profile::Find.call(params: params, dependencies: dependencies)
  end

  def create
    return if context[:find_output]
    puts 'not found'
  end

  def output
    result.output = { model: context[:find_output] }
  end
end
```

#### Example with inner operation doing the find

```ruby
Profile::Create.call(params: {
  id: 1
}, dependencies: {
  current_account: Account.find(1)
})
#<Opera::Operation::Result:0x007f99b25f0f20 @errors={}, @information={}, @executions=[:profile_schema, :find, :create, :output], @output={:model=>{:id=>1, :user_id=>1, :linkedin_uid=>nil, ...}}>
```

### Inner Operations
Expects that method returns array of `Opera::Operation::Result`

```ruby
class Profile::Create < Opera::Operation::Base
  step :validate
  step :create

  def validate; end

  def create
    result.output = { model: "Profile #{Kernel.rand(100)}" }
  end
end

class Profile::CreateMultiple < Opera::Operation::Base
  operations :create_multiple

  step :output

  def create_multiple
    (0..params[:number]).map do
      Profile::Create.call
    end
  end

  def output
    result.output = context[:create_multiple_output]
  end
end
```

```ruby
Profile::CreateMultiple.call(params: { number: 3 })

#<Opera::Operation::Result:0x0000564189f38c90 @errors={}, @information={}, @executions=[{:create_multiple=>[[:validate, :create], [:validate, :create], [:validate, :create], [:validate, :create]]}, :output], @output=[{:model=>"Profile 1"}, {:model=>"Profile 7"}, {:model=>"Profile 69"}, {:model=>"Profile 92"}]>
```

## Opera::Operation::Result - Instance Methods

Sometimes it may be useful to be able to create an instance of the `Result` with preset `output`.
It can be handy especially in specs. Then just include it in the initializer:

```
Opera::Operation::Result.new(output: 'success')
```

>
    - success? - [true, false] - Return true if no errors
    - failure? - [true, false] - Return true if any error
    - output   - [Anything]    - Return Anything
    - output=(Anything)        - Sets content of operation output
    - output!                  - Return Anything if Success, raise exception if Failure
    - add_error(key, value)    - Adds new error message
    - add_errors(Hash)         - Adds multiple error messages
    - add_information(Hash)    - Adss new information - Useful informations for developers

## Opera::Operation::Base - Instance Methods
>
    - context [Hash]          - used to pass information between steps - only for internal usage
    - params [Hash]           - immutable and received in call method
    - dependencies [Hash]     - immutable and received in call method
    - finish!                 - this method interrupts the execution of steps after is invoked

## Opera::Operation::Base - Class Methods

#### `context_reader`

The `context_reader` helper method is designed to facilitate easy access to specified keys within a `context` hash. It dynamically defines a method that acts as a getter for the value associated with a specified key, simplifying data retrieval.

#### Parameters
**key (Symbol):** The key(s) for which the getter and setter methods are to be created. These symbols should correspond to keys in the context hash.

**default (Proc, optional):** A lambda or proc that returns a default value for the key if it is not present in the context hash. This proc is lazily evaluated only when the getter is invoked and the key is not present in the hash.

#### Usage

**GOOD**

```ruby
# USE context_reader to read steps outputs from the context hash

context_reader :schema_output

validate :schema # context = { schema_output: { id: 1 } }
step :do_something

def do_something
  puts schema_output  # outputs: { id: 1 }
end
```

```ruby
# USE context_reader with 'default' option to provide default value when key is missing in the context hash

context_reader :profile, default: -> { Profile.new }

step :fetch_profile
step :do_something

def fetch_profile
  return if App.http_disabled?

  context[:profile] = ProfileFetcher.call
end

def update_profile
  profile.name = 'John'
  profile.save!
end
```

**BAD**

```ruby
# Using `context_reader` to create read-only methods that instantiate objects,
# especially when these objects are not stored or updated in the `context` hash, is not recommended.
# This approach can lead to confusion and misuse of the context hash,
# as it suggests that the object might be part of the persistent state.
context_reader :serializer, default: -> { ProfileSerializer.new }

step :output

def output
  self.result = serializer.to_json({...})
end


# A better practice is to use private methods to define read-only access to resources
# that are instantiated on the fly and not intended for storage in any state context.

step :output

def output
  self.result = serializer.to_json({...})
end

private

def serializer
  ProfileSerializer.new
end
```
**Conclusion**

For creating instance methods that are meant to be read-only and not stored within a context hash, defining these methods as private is a more suitable and clear approach compared to using context_reader with a default. This method ensures that transient dependencies remain well-encapsulated and are not confused with persistent application state.

### `context|params|depenencies`

The `context|params|depenencies` helper method is designed to enable easy access to and modification of values for specified keys within a `context` hash. This method dynamically defines both getter and setter methods for the designated keys, facilitating straightforward retrieval and update of values.

#### attr_reader, attr_accessor Parameters

**key (Symbol):** The key(s) for which the getter and setter methods are to be created. These symbols will correspond to keys in the context hash.

**default (Proc, optional):** A lambda or proc that returns a default value for the key if it is not present in the context hash. This proc is lazily evaluated only when the getter is invoked and the key is not present in the hash.

#### Usage
```ruby
context do
  attr_accessor :profile
end

step :fetch_profile
step :update_profile

def fetch_profile
  self.profile = ProfileFetcher.call # sets context[:profile]
end

def update_profile
  profile.update!(name: 'John') # reads profile from context[:profile]
end
```

```ruby
context do
  attr_accessor :profile, default: -> { Profile.new }
end
```

```ruby
context do
  attr_accessor :profile, :account
end
```

#### Other methods
>
    - step(Symbol)             - single instruction
      - return [Truthly]       - continue operation execution
      - return [False]         - stops operation execution
    - operation(Symbol)        - single instruction - requires to return Opera::Operation::Result object
      - return [Opera::Operation::Result] - stops operation STEPS execution if failure
    - validate(Symbol)         - single dry-validations - requires to return Dry::Validation::Result object
      - return [Dry::Validation::Result] - stops operation STEPS execution if any error but continue with other validations
    - transaction(*Symbols)    - list of instructions to be wrapped in transaction
      - return [Truthly]       - continue operation execution
      - return [False] - stops operation execution and breaks transaction/do rollback
    - call(params: Hash, dependencies: Hash?)
      - return [Opera::Operation::Result]

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/profinda/opera. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/opera/blob/master/CODE_OF_CONDUCT.md).


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Opera project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/profinda/opera/blob/master/CODE_OF_CONDUCT.md).
