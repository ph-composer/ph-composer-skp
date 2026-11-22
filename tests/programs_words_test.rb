# frozen_string_literal: true

require_relative "test_helper"

# The Programs findings name a user's record in the possessive; a name ending in s takes the apostrophe alone.
class ProgramsWordsTest < Minitest::Test
  Words = PhComposer::Programs::Words

  def test_the_possessive_of_a_name_ending_in_s_takes_the_apostrophe_alone
    assert_equal "Apartments'", Words.possessive("Apartments")
    assert_equal "OFFICES'", Words.possessive("OFFICES")
    assert_equal "House's", Words.possessive("House")
  end
end
