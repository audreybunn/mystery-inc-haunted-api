module NcinoConsumerApi
  class IncomeRecord < ApplicationRecord
    # Represents verified income data for loan application underwriting

    belongs_to :loan_application

    validates :loan_application_id, presence: true
    validates :gross_income, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :net_income, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :income_type, presence: true

    enum income_type: {
      salary: 'salary',
      business_income: 'business_income',
      rental_income: 'rental_income',
      investment_income: 'investment_income',
      other: 'other'
    }

    enum verification_status: {
      pending: 'pending',
      verified: 'verified',
      rejected: 'rejected',
      requires_additional_info: 'requires_additional_info'
    }

    # Calculate debt-to-income ratio helper
    def self.total_monthly_income_for_application(loan_application_id)
      where(loan_application_id: loan_application_id, verification_status: 'verified')
        .sum(:net_income)
    end

    def verified?
      verification_status == 'verified'
    end
  end
end
