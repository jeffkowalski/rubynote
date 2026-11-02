# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../rubynote'

class NotebookGuidTest < Minitest::Test
  Notebook = Struct.new(:guid, :name)

  def setup
    Rubynote.class_eval do
      define_method(:notebooks) do
        [Notebook.new('guid-1', 'Inbox'), Notebook.new('guid-2', 'Judyann Kowalski')]
      end
    end
    @rubynote = Rubynote.new
  end

  def test_resolves_exact_notebook_name_to_guid
    assert_equal 'guid-2', @rubynote.notebook_guid_for('Judyann Kowalski')
  end

  def test_unknown_notebook_name_raises
    error = assert_raises(RuntimeError) { @rubynote.notebook_guid_for('judyann kowalski') }
    assert_includes error.message, 'judyann kowalski'
  end

  def test_create_dry_run_resolves_notebook_option_to_guid
    out, = capture_io { Rubynote_CLI.start(['create', '--dry-run', '--notebook', 'Judyann Kowalski']) }
    assert_includes out, 'notebookGuid:"guid-2"'
  end

  def test_create_explicit_notebook_guid_wins_over_notebook_name
    out, = capture_io { Rubynote_CLI.start(['create', '--dry-run', '--notebook', 'Judyann Kowalski', '--notebook-guid', 'explicit']) }
    assert_includes out, 'notebookGuid:"explicit"'
  end
end
