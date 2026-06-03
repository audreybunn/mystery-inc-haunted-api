module NcinoConsumerApi
  class BusinessRelationship < ApplicationRecord
    # Represents a business entity relationship for B2B loan applications

    validates :tax_id, presence: true
    validates :legal_name, presence: true
    validates :relationship_type, presence: true

    belongs_to :loan_application, optional: true

    enum relationship_type: {
      primary_borrower: 'primary_borrower',
      guarantor: 'guarantor',
      co_borrower: 'co_borrower',
      related_entity: 'related_entity'
    }

    enum status: {
      active: 'active',
      inactive: 'inactive',
      under_review: 'under_review'
    }

    # Find existing relationship by identifiers
    def self.find_by_identifiers(tax_id:, legal_name:)
      where(tax_id: tax_id, legal_name: legal_name).first
    end

    def active?
      status == 'active'
    end
  end
end
