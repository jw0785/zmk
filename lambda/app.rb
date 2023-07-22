# frozen_string_literal: true

require 'stringio'
require './compiler'

module LambdaFunction
  # Handle a non-HTTP compile request, returning a JSON body of either the
  # compiled result or an error.
  class Handler
    REVISION = ENV.fetch('REVISION', 'unknown')

    def self.process(event:, context:)
      return { type: 'keep_alive' } if event.has_key?('keep_alive')

      parse_base64_param = ->(param, required: true) do
        if event.include?(param)
          Base64.strict_decode64(event.fetch(param))
        elsif required
          return error(status: 400, message: "Missing required argument: #{param}")
        end
      rescue ArgumentError
        return error(status: 400, message: "Invalid Base64 in #{param} input")
      end

      keymap_data  = parse_base64_param.('keymap')
      kconfig_data = parse_base64_param.('kconfig', required: false)

      # Including kconfig settings that affect the RHS require building both
      # firmware images, doubling compile time. Clients should omit rhs_kconfig
      # where possible.
      rhs_kconfig_data = parse_base64_param.('rhs_kconfig', required: false)

      result, log =
        begin
          Compiler.new.compile(keymap_data, kconfig_data, rhs_kconfig_data)
        rescue Compiler::CompileError => e
          return error(status: e.status, message: e.message, detail: e.log)
        end

      result = Base64.strict_encode64(result)

      { type: 'result', result: result, log: log, revision: REVISION }
    rescue StandardError => e
      error(status: 500, message: "Unexpected error: #{e.class}", detail: [e.message])
    end

    def self.error(status:, message:, detail: nil)
      { type: 'error', status: status, message: message, detail: detail, revision: REVISION }
    end
  end
end
