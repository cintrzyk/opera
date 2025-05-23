# frozen_string_literal: true

require 'benchmark'
require 'dry-validation'
require 'spec_helper'

module Opera
  RSpec.describe Operation::Base, type: :operation do
    let(:operation_class) do
      Class.new(Operation::Base) do
        validate :validation_1
        step :step_1

        validate do
          step :validation_2
        end

        def step_1; end

        def validation_1
          Class.new(Dry::Validation::Contract) do
            params do
            end
          end.new.call({})
        end

        def validation_2
          Class.new(Dry::Validation::Contract) do
            params do
            end
          end.new.call({})
        end
      end
    end

    subject { operation_class.call }

    describe '.configration' do
      context '#mode' do
        context 'when setting incorrect mode' do
          before do
            Operation::Config.configure do |config|
              config.mode = :invalid
            end
          end

          after do
            Operation::Config.configure do |config|
              config.mode = :development
            end
          end

          it 'raises exception' do
            puts Opera::Operation::Config.mode
            expect { subject.output }.to raise_error(/Mode is incorrect. Can be either: development or production/)
          end
        end

        context 'when in production mode' do
          context 'for #executions' do
            before do
              Operation::Config.configure do |config|
                config.mode = :production
              end
            end

            after do
              Operation::Config.configure do |config|
                config.mode = :development
              end
            end

            it 'does NOT store executions' do
              expect(subject.executions).to be_empty
            end
          end
        end
      end
    end

    describe 'dynamic attributes' do
      describe '.reader' do
        let(:operation_class) do
          Class.new(Operation::Base) do
            context_reader :foo
            context_reader :bar, default: -> { 'Z' }

            step :step_1
            step :step_2

            def step_1
              context[:foo] = 'a'
            end

            def step_2
              result.output = "#{foo}#{bar}"
            end
          end
        end

        it { expect(subject.output).to eq('aZ') }
      end

      describe '.writer' do
        let(:operation_class) do
          Class.new(Operation::Base) do
            context_writer :foo
            context_writer :bar

            step :step_1
            step :step_2

            def step_1
              self.foo = 'a'
              self.bar = 'ZZZ'
            end

            def step_2
              result.output = "#{context[:foo]}#{context[:bar]}"
            end
          end
        end

        it { expect(subject.output).to eq('aZZZ') }
      end

      describe '.accessor' do
        let(:operation_class) do
          Class.new(Operation::Base) do
            context_accessor :foo, default: -> { 'aaa' }
            context_accessor :bar

            step :step_1
            step :step_2

            def step_1
              self.bar = 'ZZZ'
            end

            def step_2
              result.output = "#{foo}#{bar}"
            end
          end
        end

        it { expect(subject.output).to eq('aaaZZZ') }
      end

      context 'for edge cases' do
        context 'when define the same method twice' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              context_accessor :foo
              params_reader :foo

              step :step_1
              step :step_2

              def step_1; end

              def step_2
                result.output = foo
              end
            end
          end

          it { expect { subject.output }.to raise_error('Method foo is already defined') }
        end

        context 'when define writer to params or dependencies' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              params_writer :foo

              step :step_1
              step :step_2

              def step_1; end

              def step_2
                result.output = foo
              end
            end
          end

          it { expect { subject.output }.to raise_error(/undefined method.+params_writer/) }
        end

        context 'when writing to reader' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              context_reader :foo, default: -> { 'foo' }

              step :step_1
              step :step_2

              def step_1
                self.foo = 'bar'
              end

              def step_2
                result.output = foo
              end
            end
          end

          it { expect { subject }.to raise_error(NoMethodError) }
        end

        context 'when defaulting to params reader' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              params_reader :foo, default: -> { bar }

              step :step_1
              step :step_2

              def step_1
                self.foo
              end

              def step_2
                result.output = foo
              end

              def bar
                'foo'
              end
            end
          end

          it { expect(subject.output).to eq('foo') }
        end

        context 'when calling operation twice' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              context_accessor :foo, default: -> { {} }

              step :step_1
              step :step_2

              def step_1
                self.foo[Kernel.rand * 1000] = 'foo'
              end

              def step_2
                result.output = self.foo
              end
            end
          end

          it 'does NOT share default values between calls' do
            expect(operation_class.call.output.keys.size).to eq(1)
            expect(operation_class.call.output.keys.size).to eq(1)
            expect(operation_class.call.output.keys.size).to eq(1)
          end
        end

        context 'when step and context have the same name' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              context do
                attr_reader :search
              end

              step :search
              step :step_2
              step :step_3

              def search
                context[:example] = 12
              end

              def step_2
                raise "Testing exceptions order"
              end

              def step_3
                result.output = :foo
              end
            end
          end

          it { expect { subject.output }.to raise_error('Method search is already defined') }
        end

        context 'new syntax' do
          context 'context block' do
            let(:operation_class) do
              Class.new(Operation::Base) do
                context do
                  attr_reader :example, default: -> { 'xxxx' }
                  attr_accessor :example2, :example3, default: -> { 'yyyy' }
                end

                alias_method :example_new, :example

                step :step_1
                step :step_2
                step :step_3

                def step_1
                  context[:example] = 12
                end

                def step_2
                  self.example2 = 13
                end

                def step_3
                  result.output = [example, example2, example3, example_new]
                end
              end
            end

            it 'returns value from context' do
              expect(operation_class.call.output).to eq([12, 13, 'yyyy', 12])
            end
          end

          context 'params and dependencies block' do
            context 'for valid syntax' do
              let(:operation_class) do
                Class.new(Operation::Base) do
                  params do
                    attr_reader :example, default: -> { 'xxxx' }
                  end
                  dependencies do
                    attr_reader :example2, default: -> { 'yyyy' }
                  end

                  step :step_1

                  def step_1
                    result.output = [example, example2]
                  end
                end
              end

              it 'returns value from context' do
                expect(operation_class.call(params: { example: 12 }, dependencies: { example2: 13 }).output).to eq([12, 13])
              end
            end

            context 'for invalid syntax' do
              let(:operation_class) do
                Class.new(Operation::Base) do
                  params do
                    attr_accessor :example, default: -> { 'xxxx' }
                  end

                  step :step_1

                  def step_1
                    result.output = [example, example2]
                  end
                end
              end

              it 'raises meaningful exception' do
                expect { operation_class }.to raise_error(/You cannot use attr_accessor inside #params/)
              end
            end
          end
        end
      end
    end

    describe '.instructions' do
      it {
        expect(operation_class.instructions).to eq([
                                                     {
                                                       kind: :validate, method: :validation_1
                                                     },
                                                     {
                                                       kind: :step, method: :step_1
                                                     },
                                                     {
                                                       instructions: [
                                                         {
                                                           kind: :step, method: :validation_2
                                                         }
                                                       ],
                                                       label: nil,
                                                       kind: :validate
                                                     }
                                                   ])
      }
    end

    describe '.result' do
      it { expect(subject).to be_an_instance_of(Opera::Operation::Result) }
    end

    describe '.call' do
      let(:params) do
        {}
      end

      let(:dependencies) do
        {}
      end

      subject { operation_class.call(params: params, dependencies: dependencies) }

      context 'for validations' do
        context 'when validation step raises an exception' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              validate do
                step :validation_1
              end
              step :step_1

              def validation_1
                raise 'exception message'
              end

              def step_1; end
            end
          end

          it 'raises exception' do
            expect { subject }.to raise_error(RuntimeError, 'exception message')
          end
        end

        context 'when validation method returns unexpected object' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              validate do
                step :validation_1
              end
              step :step_1

              def validation_1
                'unexpected string'
              end

              def step_1; end
            end
          end

          it 'raises exception' do
            expect { subject }.to raise_error(TypeError, /String is not a valid result for 'validate' step/)
          end
        end

        context 'when validation method returns Dry::Validation::Result' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              validate do
                step :validation_1
                step :validation_2
              end
              step :step_1

              def step_1; end

              def validation_1
                Class.new(Dry::Validation::Contract) do
                  params do
                    required(:profile_id).filled(:int?)
                  end
                end.new.call(params)
              end

              def validation_2
                Class.new(Dry::Validation::Contract) do
                  params do
                    required(:profile_id).filled(eql?: 102)
                  end
                end.new.call(params)
              end
            end
          end

          context 'when passing' do
            let(:params) do
              {
                profile_id: 102
              }
            end

            it 'calls validations' do
              expect(subject).to be_success
              expect(subject.errors).to be_empty
            end

            it 'calls steps' do
              expect_any_instance_of(operation_class).to receive(:step_1)
              subject
            end
          end

          context 'when failing' do
            let(:params) do
              {
                profile_id: :example
              }
            end

            it 'calls validations' do
              expect(subject).to be_failure
              expect(subject.errors).to eq(profile_id: ['must be an integer', 'must be equal to 102'])
            end

            it 'calls call validations' do
              expect_any_instance_of(operation_class).to receive(:validation_2).and_call_original
              subject
            end

            it 'never calls step' do
              expect_any_instance_of(operation_class).to_not receive(:step_1)
              subject
            end
          end
        end
      end

      context 'for steps' do
        context 'for failing step' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              step :step_2
              step :step_3
              step :step_4

              def step_1
                true
              end

              def step_2
                finish!
              end

              def step_3
                true
              end

              def step_4
                true
              end
            end
          end

          it 'calls step_1 only' do
            expect_any_instance_of(operation_class).to receive(:step_1).and_call_original
            expect_any_instance_of(operation_class).to receive(:step_2).and_call_original
            expect_any_instance_of(operation_class).to_not receive(:step_3)

            expect(subject.executions).to match_array(%i[step_1 step_2])
            expect(subject).to be_success
          end

          context 'for multiple calls' do
            subject { operation_class }

            it 'is stateless' do
              expect_any_instance_of(operation_class).to_not receive(:step_3)

              5.times do
                expect(subject.call(params: params)).to be_success
                expect(subject.call(params: params).executions).to match_array(%i[step_1 step_2])
              end
            end
          end
        end

        context 'for erroring step' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              step :step_2

              def step_1
                result.add_error(:foo, 'bar')
              end

              def step_2
                result.add_errors(foo2: ['bar2'], foo: ['bar3'])
              end
            end
          end

          it 'finishes on first erroring step' do
            expect_any_instance_of(operation_class).to receive(:step_1).and_call_original
            expect_any_instance_of(operation_class).to_not receive(:step_2)
            expect(subject.executions).to match_array(%i[step_1])
            expect(subject).to be_failure
            expect(subject.errors).to eq(
              foo: %w[bar]
            )
          end
        end
      end

      context 'for success' do
        context 'for failing step' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              success do
                step :step_1
                step :step_2
                step :step_3
              end

              step :step_4

              def step_1
                true
              end

              def step_2
                false
              end

              def step_3
                true
              end

              def step_4
                true
              end
            end
          end

          it 'calls all the steps' do
            expect_any_instance_of(operation_class).to receive(:step_1).and_call_original
            expect_any_instance_of(operation_class).to receive(:step_2).and_call_original
            expect_any_instance_of(operation_class).to receive(:step_3).and_call_original
            expect_any_instance_of(operation_class).to receive(:step_4).and_call_original
            expect(subject.executions).to match_array(%i[step_1 step_2 step_3 step_4])
            expect(subject).to be_success
          end
        end

        context 'for erroring step' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              success do
                step :step_1
                step :step_2
              end

              step :step_3
              def step_1
                result.add_error(:foo, 'bar')
              end

              def step_2
                result.add_errors(foo2: ['bar2'], foo: ['bar3'])
              end

              def step_3
                true
              end
            end
          end

          it 'finishes on first erroring step' do
            expect_any_instance_of(operation_class).to receive(:step_1).and_call_original
            expect_any_instance_of(operation_class).to receive(:step_2).and_call_original
            expect_any_instance_of(operation_class).to_not receive(:step_3)
            expect(subject.executions).to match_array(%i[step_1 step_2])
            expect(subject).to be_failure
            expect(subject.errors).to eq(
              foo: %w[bar bar3],
              foo2: %w[bar2]
            )
          end
        end
      end

      context 'for context' do
        let(:operation_class) do
          Class.new(Operation::Base) do
            step :step_1
            step :step_2

            def step_1
              context[:foo] = :bar
            end

            def step_2
              result.output = "Context #{context[:foo]}"
            end
          end
        end

        it 'shares context between steps' do
          expect(subject.output).to eq('Context bar')
        end

        it 'DOES NOT have access to context from outside of operation' do
          expect(subject.methods).to_not include(:context)
        end
      end

      context 'for accessors/readers' do
        subject { operation_class.call(params: {}, dependencies: {}) }

        let(:operation_class) do
          Class.new(Operation::Base) do
            params_reader :bar, default: -> { :bar }
            dependencies_reader :foo, default: -> { :foo }
            context_reader :baz

            step :step_1
            step :step_2

            def step_1; end

            def step_2
              result.output = [foo, bar, baz]
            end
          end
        end

        it 'returns default values' do
          expect(subject.output).to eq([:foo, :bar, nil])
        end
      end

      context 'for output' do
        let(:operation_class) do
          Class.new(Operation::Base) do
            step :step_1
            step :step_2

            def step_1
              result.output = { model: { foo: :bar } }
            end

            def step_2
              new_output = result.output.merge(status: :ok)
              result.output = new_output
            end
          end
        end

        it 'returns correct output' do
          expect(subject.output).to eq(model: { foo: :bar }, status: :ok)
        end
      end

      context 'for configuration' do
        let(:transaction_class) do
          Class.new do
            def self.transaction
              yield
            end
          end
        end

        before do
          Operation::Config.configure do |config|
            config.transaction_class = transaction_class
          end
        end

        subject { operation_class }

        context 'when we use defaults' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              step :step_2

              def step_1; end

              def step_2; end
            end
          end

          it 'uses global transaction' do
            expect(Operation::Config.transaction_class).to eq(transaction_class)
            expect(subject.config.transaction_class).to eq(transaction_class)
          end
        end

        context 'when we use specified configuration' do
          let(:new_transaction_class) do
            Class.new do
              def self.transaction
                yield
              end
            end
          end

          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              step :step_2

              def step_1; end

              def step_2; end
            end
          end

          before do
            operation_class.configure do |config|
              config.transaction_class = new_transaction_class
            end
          end

          it 'uses specifed transaction' do
            expect(Operation::Config.transaction_class).to eq(transaction_class)
            expect(subject.config.transaction_class).to eq(new_transaction_class)
          end
        end
      end

      context 'for transaction' do
        let(:transaction_class) do
          Class.new do
            def self.transaction
              yield
            end
          end
        end

        let(:operation_class) do
          Class.new(Operation::Base) do
            step :step_1
            step :step_2
            transaction do
              step :step_3
              step :step_4
            end
            step :step_5

            def step_1
              true
            end

            def step_2
              true
            end

            def step_3
              true
            end

            def step_4
              1
            end

            def step_5
              true
            end
          end
        end

        before do
          Operation::Config.configure do |config|
            config.transaction_class = transaction_class
          end
        end

        it 'evaluates all steps' do
          expect(subject.executions).to match_array(%i[step_1 step_2 step_3 step_4 step_5])
        end

        context 'for finished execution step inside transaction' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              step :step_2
              transaction do
                step :step_3
                step :step_4
              end
              step :step_5

              def step_1
                false
              end

              def step_2
                true
              end

              def step_3
                finish!
              end

              def step_4
                true
              end

              def step_5
                true
              end
            end
          end

          it 'evaluates 3 steps' do
            expect(subject.executions).to match_array(%i[step_1 step_2 step_3])
          end

          it 'ends with success' do
            expect(subject).to be_success
          end

          it 'never calls TransactionRollback' do
            expect_any_instance_of(Opera::Operation::Instructions::Executors::Transaction).to_not receive(:transaction_error)
            subject
          end
        end

        context 'for transaction options' do
          let(:transaction_class) do
            Class.new do
              def self.transaction(args)
                yield
              end
            end
          end
          let(:transaction_options) do
            { foo: :bar }
          end

          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              transaction do
                step :step_3
              end

              def step_1
                true
              end

              def step_3
                true
              end
            end
          end

          before do
            Operation::Config.configure do |config|
              config.transaction_class = transaction_class
              config.transaction_options = transaction_options
            end
          end

          it 'passes transaction options to transaction class' do
            expect(transaction_class).to receive(:transaction).with(transaction_options)
            subject
          end
        end
      end

      context 'for instrumentation' do
        let(:instrumentation_wrapper) do
          Class.new(Opera::Operation::Instrumentation::Base) do

            def self.instrument(operation, name:, level:)
              puts "Trace #{name} with level #{level}"
              yield
            end
          end
        end

        let(:operation_class) do
          FakeName = Class.new(Operation::Base) do
            step :step_1
            step :step_2
            step :step_3
            step :step_4
            step :step_5

            def step_1
              true
            end

            def step_2
              true
            end

            def step_3
              true
            end

            def step_4
              1
            end

            def step_5
              true
            end
          end
        end

        before do
          Operation::Config.configure do |config|
            config.instrumentation_class = instrumentation_wrapper
          end
        end

        it 'evaluates all steps' do
          expect(subject.executions).to match_array(%i[step_1 step_2 step_3 step_4 step_5])
        end

        it 'calls instrumentation with correct params' do
          expect(instrumentation_wrapper).to receive(:instrument).with(anything, name: 'Opera::FakeName', level: :operation).once.and_call_original
          expect(instrumentation_wrapper).to receive(:instrument).with(anything, name: '#step_1', level: :step).once.and_call_original
          expect(instrumentation_wrapper).to receive(:instrument).with(anything, name: '#step_2', level: :step).once.and_call_original
          expect(instrumentation_wrapper).to receive(:instrument).with(anything, name: '#step_3', level: :step).once.and_call_original
          expect(instrumentation_wrapper).to receive(:instrument).with(anything, name: '#step_4', level: :step).once.and_call_original
          expect(instrumentation_wrapper).to receive(:instrument).with(anything, name: '#step_5', level: :step).once

          subject
        end
      end

      context 'for operation' do
        let(:failing_operation) do
          Class.new(Operation::Base) do
            step :step_1
            step :step_2

            def step_1
              result.add_error(:base, 'Inner error')
            end

            def step_2; end
          end
        end

        let(:valid_operation) do
          Class.new(Operation::Base) do
            step :step_44

            def step_44
              result.output = { example: 'output' }
            end
          end
        end

        let(:operation_class) do
          Class.new(Operation::Base) do
            operation :operation_1
            step :step_1

            def operation_1
              dependencies[:injected_operation].call
            end

            def step_1
              result.output = context[:operation_1_output]
            end
          end
        end

        context 'when the inner operation fails' do
          let(:dependencies) do
            { injected_operation: failing_operation }
          end

          it 'ends with failure' do
            expect(subject).to be_failure
          end

          it 'adds inner errors into the result' do
            expect(subject.errors).to have_key(:base)
          end

          it 'adds contains the inner executions in the executions array' do
            expect(subject.executions).to eq([{ operation_1: [:step_1] }])
          end
        end

        context 'when the inner operation is valid' do
          let(:dependencies) do
            { injected_operation: valid_operation }
          end

          it 'ends with failure' do
            expect(subject).to be_success
          end

          it 'adds contains the inner executions in the executions array' do
            expect(subject.executions).to eq([{ operation_1: [:step_44] }, :step_1])
          end

          it 'adds the output to the context of the operation' do
            expect(subject.output).to have_key(:example)
          end
        end
      end

      context 'for operations' do
        let(:failing_operation) do
          Class.new(Operation::Base) do
            step :step_1

            def step_1
              result.add_error(:base, 'Inner error')
            end
          end
        end

        let(:valid_operation) do
          Class.new(Operation::Base) do
            step :step_1
            step :step_2

            def step_1; end

            def step_2
              result.output = { example: 'output' }
            end
          end
        end

        let(:operation_class) do
          Class.new(Operation::Base) do
            operations :operations_collection
            step :step_1

            def operations_collection
              (1..3).map do
                dependencies[:injected_operation].call
              end
            end

            def step_1
              result.output = context[:operations_collection_output]
            end
          end
        end

        context 'when the inner operation fails' do
          let(:dependencies) do
            { injected_operation: failing_operation }
          end

          it 'ends with failure' do
            expect(subject).to be_failure
          end

          it 'adds inner errors into the result' do
            expect(subject.errors).to have_key(:base)
          end
        end

        context 'when the inner operation is valid' do
          let(:dependencies) do
            { injected_operation: valid_operation }
          end

          it 'ends with failure' do
            expect(subject).to be_success
          end

          it 'adds contains the inner executions in the executions array' do
            expect(subject.executions).to eq([{
                                               operations_collection: [%i[step_1 step_2],
                                                                       %i[step_1 step_2],
                                                                       %i[step_1 step_2]]
                                             }, :step_1])
          end

          it 'adds the output to the context of the operations' do
            expect(subject.output.size).to eq(3)
            subject.output.each do |output|
              expect(output).to eq(example: 'output')
            end
          end
        end
      end

      context 'for benchmark' do
        let(:operation_class) do
          Class.new(Operation::Base) do
            step :step_1
            step :step_2
            benchmark :step_3
            benchmark :step_4
            step :step_5

            def step_1
              false
            end

            def step_2
              true
            end

            def step_3
              true
            end

            def step_4
              1
            end

            def step_5
              true
            end
          end
        end

        it 'ends with success' do
          expect(subject).to be_success
        end

        it 'add benchmark info to result' do
          expect(subject.information[:step_3]).to have_key(:real)
          expect(subject.information[:step_3]).to have_key(:total)
          expect(subject.information[:step_4]).to have_key(:real)
          expect(subject.information[:step_4]).to have_key(:total)
        end

        context 'for failing step' do
          let(:operation_class) do
            Class.new(Operation::Base) do
              step :step_1
              step :step_2
              benchmark :example do
                step :step_3
                step :step_4
              end
              step :step_5

              def step_1
                false
              end

              def step_2
                false
              end

              def step_3
                finish!
              end

              def step_4
                1
              end

              def step_5
                true
              end
            end
          end

          it 'executes only first 3 instructions' do
            expect(subject.executions).to match_array(%i[step_1 step_2 step_3])
          end

          it 'add benchmark info to result' do
            expect(subject.information[:example]).to have_key(:real)
            expect(subject.information[:example]).to have_key(:total)
          end
        end
      end

      context 'for finish_if' do
        let(:operation_class) do
          Class.new(Operation::Base) do
            step :step_1
            finish_if :condition_1
            step :step_2
            finish_if :condition_2
            step :step_5

            def step_1
              false
            end

            def condition_1
              nil
            end

            def step_2
              'foo'
            end

            def condition_2
              true
            end

            def step_5
              true
            end
          end
        end

        it 'ends with success' do
          expect(subject).to be_success
        end

        it 'executions stop on step_2' do
          expect(subject.executions).to match_array(%i[step_1 condition_1 step_2 condition_2])
        end
      end
    end
  end
end
