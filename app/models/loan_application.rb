module NcinoConsumerApi
  class LoanApplication < ApplicationRecord
    # Represents a loan application received from the nCino platform

    validates :guid, presence: true, uniqueness: true
    validates :status, presence: true
    validates :applicant_name, presence: true

    has_many :income_records, dependent: :destroy
    has_one :business_relationship

    enum status: {
      pending: 'pending',
      in_review: 'in_review',
      approved: 'approved',
      rejected: 'rejected',
      withdrawn: 'withdrawn'
    }

    # Scopes for common queries
    scope :active, -> { where(status: ['pending', 'in_review']) }
    scope :recent, -> { order(created_at: :desc).limit(100) }

    def complete?
      status.in?(['approved', 'rejected', 'withdrawn'])
    end

    def needs_income_verification?
      income_records.exists? && income_records.any? { |r| r.verification_status == 'pending' }
    end
  end
end
