module NcinoConsumerApi
  module ApplicationSync
    class IncomeMapper
      # Maps external income data from various sources to our internal schema
      # Handles conversions from different third-party income verification providers
      #
      # NOTE: The reported RecordMappingError ("income record ... has not been
      # created yet. Nothing to update.") is raised in
      # income_update_sync_handler.rb#update_application_mapping_app when an
      # UPDATE sync event arrives before the corresponding CREATE event.
      #
      # The handler should treat a missing record as an UPSERT (create-if-missing)
      # rather than raising. This mapper now exposes `map` for upsert use so the
      # handler can build a valid attribute hash even when no record exists yet.

      def initialize(source_data, source_type:)
        @source_data = (source_data || {}).to_h
        @source_type = source_type
      end

      def map
        case @source_type
        when 'plaid'
          map_plaid_income
        when 'argyle'
          map_argyle_income
        when 'finicity'
          map_finicity_income
        else
          raise RecordMappingError, "Unknown source type: #{@source_type}"
        end
      end

      private

      def map_plaid_income
        validate_required_fields!(@source_data, %w[amount_gross amount_net type])

        # Map Plaid income fields to our schema
        # FIX: gross/net were previously swapped.
        {
          gross_income: @source_data['amount_gross'],
          net_income: @source_data['amount_net'],
          income_type: normalize_income_type(@source_data['type']),
          verification_status: 'verified',
          source_provider: 'plaid',
          verified_at: Time.current
        }
      end

      def map_argyle_income
        validate_required_fields!(@source_data, %w[gross_pay net_pay income_category])

        {
          gross_income: @source_data['gross_pay'],
          net_income: @source_data['net_pay'],
          income_type: normalize_income_type(@source_data['income_category']),
          verification_status: 'verified',
          source_provider: 'argyle',
          verified_at: Time.current
        }
      end

      def map_finicity_income
        validate_required_fields!(@source_data, %w[gross net category])

        {
          gross_income: @source_data['gross'],
          net_income: @source_data['net'],
          income_type: normalize_income_type(@source_data['category']),
          verification_status: 'verified',
          source_provider: 'finicity',
          verified_at: Time.current
        }
      end

      def normalize_income_type(external_type)
        # Guard against nil so a missing/blank type does not raise NoMethodError.
        return 'other' if external_type.nil? || external_type.to_s.strip.empty?

        # Map external income type strings to our internal enum values
        type_mapping = {
          'salary' => 'salary',
          'wages' => 'salary',
          'business' => 'business_income',
          'self_employment' => 'business_income',
          'rental' => 'rental_income',
          'investment' => 'investment_income',
          'dividends' => 'investment_income'
        }

        type_mapping[external_type.to_s.downcase] || 'other'
      end

      def validate_required_fields!(data, required_fields)
        # Treat blank/nil values as missing, not just absent keys.
        missing_fields = required_fields.select do |field|
          value = data[field]
          value.nil? || (value.respond_to?(:empty?) && value.empty?)
        end

        if missing_fields.any?
          raise RecordMappingError, "Missing required fields: #{missing_fields.join(', ')}"
        end
      end

      class RecordMappingError < StandardError; end
    end
  end
end