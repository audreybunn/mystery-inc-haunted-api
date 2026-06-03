module NcinoConsumerApi
  module ApplicationSync
    class IncomeMapper
      # Maps external income data from various sources to our internal schema
      # Handles conversions from different third-party income verification providers

      def initialize(source_data, source_type:)
        @source_data = source_data
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
        # FIX: gross_income must map from amount_gross, net_income from amount_net
        {
          gross_income: @source_data['amount_gross'],
          net_income: @source_data['amount_net'],
          income_type: normalize_income_type(@source_data['type']),
          verification_status: 'verified',
          source_provider: 'plaid',
          verified_at: Time.current
        }
      rescue KeyError => e
        Rails.logger.error "[IncomeMapper] Missing required field for Plaid income: #{e.message}"
        raise RecordMappingError, "income record for Plaid source missing required field: #{e.message}"
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
        # Map external income type strings to our internal enum values
        # FIX: guard against nil/blank external_type to avoid NoMethodError on downcase
        return 'other' if external_type.nil? || external_type.to_s.strip.empty?

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
        missing_fields = required_fields - data.keys
        if missing_fields.any?
          raise RecordMappingError, "Missing required fields: #{missing_fields.join(', ')}"
        end
      end

      class RecordMappingError < StandardError; end
    end
  end
end