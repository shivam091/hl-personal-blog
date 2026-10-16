# encoding: UTF-8

# So specs never reach Google or need real credentials.
module GoogleApiHelpers
  GOOGLE_TEST_KEY = OpenSSL::PKey::RSA.new(2048)

  def google_stubs
    @google_stubs ||= Faraday::Adapter::Test::Stubs.new
  end

  # Stubs matched first win, so a spec's own token stub, set up before the
  # client, overrides this one.
  def google_client(scope: "scope", client_email: "sync@project.iam.gserviceaccount.com", private_key: GOOGLE_TEST_KEY.to_pem, **options)
    google_stubs.post(Google::ApiClient::TOKEN_URL) do
      [200, {}, {access_token: "token", expires_in: 3599}.to_json]
    end
    connection = Faraday.new(request: {params_encoder: Faraday::FlatParamsEncoder}) do |faraday|
      faraday.response :raise_error
      faraday.adapter :test, google_stubs
    end
    Google::ApiClient.new(scope: scope, client_email: client_email, private_key: private_key,
      cache: ActiveSupport::Cache::MemoryStore.new, connection: connection, **options)
  end

  # Flat-encoded, as the real one is, so a repeated parameter reaches the
  # stub as Google would see it.
  def google_key_client(api_key: "test-key")
    connection = Faraday.new(request: {params_encoder: Faraday::FlatParamsEncoder}) do |faraday|
      faraday.response :raise_error
      faraday.adapter :test, google_stubs
    end
    Google::KeyClient.new(api_key: api_key, connection: connection)
  end
end

RSpec.configure { |config| config.include GoogleApiHelpers }
