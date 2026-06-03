require 'active_support/message_encryptor'

module NcinoConsumerApi
  class TokenEncryptor
    # Encrypts and decrypts sensitive authentication tokens
    # Uses ActiveSupport::MessageEncryptor for secure token handling

    class << self
      def encrypt(token)
        encryptor.encrypt_and_sign(token)
      end

      def decrypt(encrypted_token)
        encryptor.decrypt_and_verify(encrypted_token)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage,
             ActiveSupport::MessageVerifier::InvalidSignature => e
        Rails.logger.error "[TokenEncryptor] Error #{e.class} raised. Message: #{e.message}"
        raise DecryptionError, "Failed to decrypt token: #{e.message}"
      end

      private

      def encryptor
        @encryptor ||= begin
          # Generate encryption key from secret base.
          # The key length MUST match the cipher's required key size.
          # aes-256-gcm requires a 32-byte key.
          secret = ENV.fetch('SECRET_KEY_BASE', 'default_secret_for_development_only')

          cipher = 'aes-256-gcm'
          key_len = ActiveSupport::MessageEncryptor.key_len(cipher) # 32 for aes-256-gcm

          key = ActiveSupport::KeyGenerator.new(secret).generate_key('token_encryption', key_len)

          ActiveSupport::MessageEncryptor.new(key, cipher: cipher)
        end
      end
    end

    class DecryptionError < StandardError; end
  end
end