# NcinoConsumerApi

Consumer API service for nCino loan application processing and business relationship management.

## Overview

NcinoConsumerApi is a Ruby on Rails service that handles:
- Loan application ingestion from SQS queues
- Business relationship search and validation
- Income record synchronization
- Secure token management for external integrations

## Tech Stack

- **Ruby on Rails** 7.0
- **MySQL** for primary data storage
- **Shoryuken** for SQS message processing
- **Redlock** for distributed locking across workers
- **ActiveSupport::MessageEncryptor** for secure token handling

## Key Components

### Jobs
- `UpsertApplicationJob` - Processes loan application messages from SQS
- `UpsertRecordJob` - Handles record updates with distributed lock coordination

### Services
- `BusinessRelationshipSearch` - Searches for existing business relationships via API
- `ApplicationSync::IncomeMapper` - Maps external income data to internal schema

### Libraries
- `TokenEncryptor` - Encrypts and decrypts sensitive authentication tokens

## Development

This service integrates with the nCino platform and requires proper configuration of:
- Database credentials
- SQS queue names
- API endpoint URLs
- Encryption keys

---

## Demo Note

This repository is part of the **Mystery Inc.** log-triage hackathon demo. It contains intentionally planted bugs that match real production error signatures from DataDog logs. An AI agent will analyze error logs and open pull requests with fixes to demonstrate automated incident triage and remediation.

**Do not use this code in production.**
