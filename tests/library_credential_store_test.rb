# frozen_string_literal: true

require_relative "test_helper"

# The credential store's own rules, against an in-memory backend: the OS backends are host evidence.
class LibraryCredentialStoreTest < PhComposerTestCase
  Store = PhComposer::Library::Connection::CredentialStore

  def setup
    super
    @backend = HostedLibraryFixtures::MemoryCredentials.new
    Store.backend = @backend
  end

  def code
    yield
    flunk "expected a refusal"
  rescue PhComposer::Library::Error => error
    error.code
  end

  def test_write_replace_read_and_delete_one_item_per_provider_and_connection
    assert_nil Store.read("test.hosted", "connection-1")
    Store.write("test.hosted", "connection-1", "synthetic-1")
    Store.write("test.hosted", "connection-2", "synthetic-2")
    Store.write("test.hosted", "connection-1", "synthetic-1b")
    assert_equal %w[synthetic-1b synthetic-2],
                 [Store.read("test.hosted", "connection-1"), Store.read("test.hosted", "connection-2")]
    assert_equal Encoding::BINARY, @backend.items.fetch(%w[test.hosted connection-1]).encoding
    assert Store.delete("test.hosted", "connection-1")
    refute Store.delete("test.hosted", "connection-1")
    assert_nil Store.read("test.hosted", "connection-1")
  end

  def test_keys_must_be_public_ids_and_values_bounded_text
    ["Synthetic Firm", "a@example.invalid", "", nil, "x" * 129].each do |bad|
      assert_equal "library.credential_store_failed", code { Store.write("test.hosted", bad, "value") }, bad.inspect
      assert_equal "library.credential_store_failed", code { Store.read(bad, "connection-1") }, bad.inspect
    end
    assert_equal "library.credential_store_failed", code { Store.write("test.hosted", "c", "") }
    assert_equal "library.credential_store_failed",
                 code { Store.write("test.hosted", "c", "x" * (Store::MAX_BYTES + 1)) }
    Store.write("test.hosted", "c", "x" * Store::MAX_BYTES)
    assert_empty(@backend.items.keys.reject { |key| key == %w[test.hosted c] })
  end

  # A failing backend's own text never reaches the caller; a platform without a store says so.
  def test_backend_failures_keep_only_a_code
    failing = Object.new
    failing.define_singleton_method(:write) { |*_arguments| raise IOError, "keychain item synthetic-secret locked" }
    Store.backend = failing
    error = assert_raises(PhComposer::Library::Error) { Store.write("test.hosted", "c", "synthetic-secret") }
    assert_equal "library.credential_store_failed", error.code
    refute_includes error.message, "synthetic-secret"
    assert_nil error.cause
    Store.backend = Store::Unavailable.new
    assert_equal "library.credential_store_unavailable", code { Store.read("test.hosted", "c") }
  end

  # Loading this file on a platform without Fiddle or the OS library must not fail; only use does.
  def test_platform_backends_load_nothing_until_used
    assert_instance_of Store::Keychain, Store::Keychain.new
    assert_instance_of Store::CredentialManager, Store::CredentialManager.new
    Store.backend = nil
    expected = if RUBY_PLATFORM.include?("darwin") then Store::Keychain
               elsif Gem.win_platform? then Store::CredentialManager
               else Store::Unavailable
               end
    assert_instance_of expected, Store.backend
  end
end
