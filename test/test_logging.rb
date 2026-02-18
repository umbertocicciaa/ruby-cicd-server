# frozen_string_literal: true

require_relative 'test_helper'

class TestLogging < Minitest::Test
  def setup
    # Reset the cached logger so each test gets a fresh one
    Logging.instance_variable_set(:@logger, nil)
  end

  # --- MultiLogger ---
  def test_multi_logger_broadcasts_to_all_loggers
    buf1 = StringIO.new
    buf2 = StringIO.new
    l1 = Logger.new(buf1)
    l2 = Logger.new(buf2)
    l1.level = Logger::DEBUG
    l2.level = Logger::DEBUG

    ml = Logging::MultiLogger.new(l1, l2)
    ml.info('hello multi')

    assert_match(/hello multi/, buf1.string)
    assert_match(/hello multi/, buf2.string)
  end

  def test_multi_logger_all_levels
    buf = StringIO.new
    l = Logger.new(buf)
    l.level = Logger::DEBUG
    ml = Logging::MultiLogger.new(l)

    %i[debug info warn error fatal].each do |level|
      ml.send(level, "test_#{level}")
    end

    %w[test_debug test_info test_warn test_error test_fatal].each do |msg|
      assert_match(/#{msg}/, buf.string)
    end
  end

  def test_multi_logger_set_level
    buf = StringIO.new
    l = Logger.new(buf)
    ml = Logging::MultiLogger.new(l)

    ml.level = Logger::ERROR
    assert_equal Logger::ERROR, l.level
  end

  def test_multi_logger_close
    buf = StringIO.new
    l = Logger.new(buf)
    ml = Logging::MultiLogger.new(l)

    # Should not raise
    ml.close
  end

  # --- Logging module methods ---
  def test_info_method
    out, _err = capture_io { Logging.info('info_test_msg') }
    assert_match(/info_test_msg/, out)
  end

  def test_debug_method
    # Debug goes to file only (console level is INFO), so just ensure no error
    capture_io { Logging.debug('debug_test_msg') }
    # No assertion on output since console level filters debug
  end

  def test_warn_method
    out, _err = capture_io { Logging.warn('warn_test_msg') }
    assert_match(/warn_test_msg/, out)
  end

  def test_error_method
    out, _err = capture_io { Logging.error('error_test_msg') }
    assert_match(/error_test_msg/, out)
  end

  def test_fatal_method
    out, _err = capture_io { Logging.fatal('fatal_test_msg') }
    assert_match(/fatal_test_msg/, out)
  end

  def test_success_method
    out, _err = capture_io { Logging.success('success_msg') }
    assert_match(/success_msg/, out)
  end

  def test_step_method
    out, _err = capture_io { Logging.step('step_title') }
    assert_match(/step_title/, out)
    assert_match(/={60}/, out) # separator
  end

  def test_timed_method_success
    out, _err = capture_io do
      result = Logging.timed('test_block') { 42 }
      assert_equal 42, result
    end
    assert_match(/Starting: test_block/, out)
    assert_match(/Completed: test_block/, out)
  end

  def test_timed_method_failure
    assert_raises(RuntimeError) do
      capture_io do
        Logging.timed('fail_block') { raise 'boom' }
      end
    end
  end

  def test_section_method
    out, _err = capture_io { Logging.section('section_title') }
    assert_match(/section_title/, out)
  end

  # --- COLORS constant ---
  def test_colors_frozen
    assert Logging::COLORS.frozen?
  end

  def test_colors_has_reset
    assert Logging::COLORS.key?(:reset)
  end

  # --- severity_color (private) ---
  def test_severity_color_debug
    color = Logging.send(:severity_color, 'DEBUG')
    assert_equal Logging::COLORS[:gray], color
  end

  def test_severity_color_info
    color = Logging.send(:severity_color, 'INFO')
    assert_equal Logging::COLORS[:cyan], color
  end

  def test_severity_color_warn
    color = Logging.send(:severity_color, 'WARN')
    assert_equal Logging::COLORS[:yellow], color
  end

  def test_severity_color_error
    color = Logging.send(:severity_color, 'ERROR')
    assert_equal Logging::COLORS[:red], color
  end

  def test_severity_color_fatal
    color = Logging.send(:severity_color, 'FATAL')
    assert_equal Logging::COLORS[:red], color
  end

  def test_severity_color_unknown
    color = Logging.send(:severity_color, 'UNKNOWN')
    assert_equal Logging::COLORS[:reset], color
  end
end
