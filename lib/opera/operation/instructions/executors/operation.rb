# frozen_string_literal: true

module Opera
  module Operation
    module Instructions
      module Executors
        class Operation < Executor
          def call(instruction)
            instruction[:kind] = :step
            operation_result = super
            save_information(operation_result)

            if operation_result.success?
              add_instruction_output(instruction, operation_result.output)
              execution = result.executions.pop
              result.executions << { execution => operation_result.executions }
            else
              result.add_errors(operation_result.errors)
              result.add_exceptions(operation_result.exceptions)
            end
          end

          private

          def save_information(operation_result)
            return unless operation_result.respond_to?(:information)

            result.add_information(operation_result.information)
          end
        end
      end
    end
  end
end
