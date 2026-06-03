require 'httparty'

module NcinoConsumerApi
  class BusinessRelationshipSearch
    include HTTParty
    # The nCino business-banking API lives under the /business-banking path on
    # the regional host (e.g. us.api.ncino.com). Default to the correct host so
    # requests are routed to the proper service.
    base_uri ENV.fetch('NCINO_API_BASE_URL', 'https://us.api.ncino.com/business-banking')

    def initialize(tax_id:, legal_name:)
      @tax_id = tax_id
      @legal_name = legal_name
    end

    # Search for existing business relationship in the nCino platform
    # Returns existing relationship ID if found, nil otherwise
    def search
      response = self.class.post(
        '/v1/relationships/businesses/search',
        body: build_request_body.to_json,
        headers: auth_headers,
        timeout: 10
      )

      if response.success?
        parse_response(response)
      else
        log_error(response)
        raise SearchError, "Error searching for existing business relationship: Received status #{response.code} for /v1/relationships/businesses/search"
      end
    rescue HTTParty::Error, Net::OpenTimeout => e
      Rails.logger.error "[BusinessRelationshipSearch] HTTP error: #{e.message}"
      raise SearchError, "Network error searching for business relationship: #{e.message}"
    end

    private

    # Build the JSON request body for the POST search endpoint.
    # The search criteria (tax_id and legal_name) must be sent in the body,
    # not as query string parameters.
    def build_request_body
      {
        tax_id: @tax_id,
        legal_name: @legal_name,
        include_inactive: false
      }
    end

    def auth_headers
      {
        'Authorization' => "Bearer #{TokenEncryptor.decrypt(ENV['NCINO_API_TOKEN'])}",
        'Content-Type' => 'application/json',
        'Accept' => 'application/json',
        'X-API-Version' => '2.0'
      }
    end

    def parse_response(response)
      body = JSON.parse(response.body)
      relationships = body.dig('data', 'relationships') || []

      if relationships.any?
        Rails.logger.info "[BusinessRelationshipSearch] Found #{relationships.size} existing relationship(s)"
        relationships.first['id']
      else
        Rails.logger.info "[BusinessRelationshipSearch] No existing relationship found"
        nil
      end
    end

    def log_error(response)
      Rails.logger.error "[BusinessRelationshipSearch] Search failed with status #{response.code}"
      Rails.logger.error "[BusinessRelationshipSearch] Response body: #{response.body}"
    end

    class SearchError < StandardError; end
  end
end