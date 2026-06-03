require 'active_support/message_encryptor'

module NcinoConsumerApi
  class TokenEncryptor
    # Encrypts and decrypts sensitive authentication tokens
    # Uses ActiveSupport::MessageEncryptor for secure token handling

    # AES-256-CBC requires a 32-byte key. The key length MUST match the
    # cipher's expected key length or decryption will fail with
    # "mismatched digest" / InvalidMessage errors.
    CIPHER = 'aes-256-cbc'.freeze
    KEY_LEN = ActiveSupport::MessageEncryptor.key_len(CIPHER) # => 32 for aes-256-cbc

    class << self
      def encrypt(token)
        encryptor.encrypt_and_sign(token)
      end

      def decrypt(encrypted_token)
        encryptor.decrypt_and_verify(encrypted_token)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage => e
        Rails.logger.error "[TokenEncryptor] Error #{e.class} raised. Message: #{e.message}"
        raise DecryptionError, "Failed to decrypt token: #{e.message}"
      end

      private

      def encryptor
        @encryptor ||= begin
          # Use a stable secret. Fail fast in non-development environments
          # rather than silently falling back to a default secret, which
          # would derive a different key and break decryption of existing
          # tokens (the root cause of "mismatched digest" errors).
          secret = secret_key_base

          # Derive a key whose length matches the cipher (32 bytes for AES-256).
          key = ActiveSupport::KeyGenerator.new(secret).generate_key(
            'token_encryption',
            KEY_LEN
          )

          ActiveSupport::MessageEncryptor.new(key, cipher: CIPHER)
        end
      end

      def secret_key_base
        secret =
          if defined?(Rails) && Rails.application&.secret_key_base
            Rails.application.secret_key_base
          else
            ENV['SECRET_KEY_BASE']
          end

        if secret.blank?
          if defined?(Rails) && !Rails.env.development? && !Rails.env.test?
            raise DecryptionError,
                  'SECRET_KEY_BASE is not set; refusing to use a default secret in production.'
          end
          secret = 'default_secret_for_development_only'
        end

        secret
      end
    end

    class DecryptionError < StandardError; end
  end
end