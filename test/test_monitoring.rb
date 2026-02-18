# frozen_string_literal: true

require_relative 'test_helper'

class TestMonitoringMetrics < Minitest::Test
  def test_new_metrics_defaults
    m = Monitoring::Metrics.new
    assert_equal 0, m.total_runs
    assert_equal 0, m.successful_runs
    assert_equal 0, m.failed_runs
    assert_equal 0.0, m.total_execution_time
    assert_equal({}, m.errors.select { true }) # convert default hash
  end

  def test_average_execution_time_zero_runs
    m = Monitoring::Metrics.new
    assert_equal 0, m.average_execution_time
  end

  def test_average_execution_time_with_runs
    m = Monitoring::Metrics.new
    m.total_runs = 4
    m.total_execution_time = 10.0
    assert_equal 2.5, m.average_execution_time
  end

  def test_success_rate_zero_runs
    m = Monitoring::Metrics.new
    assert_equal 0, m.success_rate
  end

  def test_success_rate_with_runs
    m = Monitoring::Metrics.new
    m.total_runs = 10
    m.successful_runs = 7
    assert_equal 70.0, m.success_rate
  end

  def test_to_h
    m = Monitoring::Metrics.new
    m.total_runs = 3
    m.successful_runs = 2
    m.failed_runs = 1
    m.total_execution_time = 6.789
    m.errors['SomeError'] = 1

    h = m.to_h
    assert_equal 3, h[:total_runs]
    assert_equal 2, h[:successful_runs]
    assert_equal 1, h[:failed_runs]
    assert_equal 6.79, h[:total_execution_time]
    assert_in_delta 2.26, h[:average_execution_time], 0.01
    assert_in_delta 66.67, h[:success_rate], 0.01
    assert_equal({ 'SomeError' => 1 }, h[:errors].select { true })
  end

  def test_to_json
    m = Monitoring::Metrics.new
    m.total_runs = 1
    json = m.to_json
    parsed = JSON.parse(json)
    assert_equal 1, parsed['total_runs']
  end

  def test_from_hash
    hash = {
      'total_runs' => 5,
      'successful_runs' => 3,
      'failed_runs' => 2,
      'total_execution_time' => 12.5,
      'errors' => { 'BuildError' => 2 }
    }

    m = Monitoring::Metrics.from_hash(hash)
    assert_equal 5, m.total_runs
    assert_equal 3, m.successful_runs
    assert_equal 2, m.failed_runs
    assert_equal 12.5, m.total_execution_time
    assert_equal 2, m.errors['BuildError']
  end

  def test_from_hash_with_missing_keys
    m = Monitoring::Metrics.from_hash({})
    assert_equal 0, m.total_runs
    assert_equal 0, m.successful_runs
    assert_equal 0, m.failed_runs
    assert_equal 0.0, m.total_execution_time
  end
end

class TestMonitoringModule < Minitest::Test
  def setup
    @original_metrics_file = Monitoring::METRICS_FILE
    @temp_dir = Dir.mktmpdir('monitoring_test')
    @temp_file = File.join(@temp_dir, 'test_metrics.json')

    # Redirect METRICS_FILE to temp location
    Monitoring.send(:remove_const, :METRICS_FILE) if Monitoring.const_defined?(:METRICS_FILE)
    Monitoring.const_set(:METRICS_FILE, @temp_file)

    Monitoring.send(:remove_const, :METRICS_DIR) if Monitoring.const_defined?(:METRICS_DIR)
    Monitoring.const_set(:METRICS_DIR, @temp_dir)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)

    Monitoring.send(:remove_const, :METRICS_FILE) if Monitoring.const_defined?(:METRICS_FILE)
    Monitoring.const_set(:METRICS_FILE, @original_metrics_file)

    Monitoring.send(:remove_const, :METRICS_DIR) if Monitoring.const_defined?(:METRICS_DIR)
    Monitoring.const_set(:METRICS_DIR, File.dirname(@original_metrics_file))
  end

  def test_record_pipeline_success
    capture_io do
      Monitoring.record_pipeline_success(1.5)
    end

    m = Monitoring.get_metrics
    assert_equal 1, m.total_runs
    assert_equal 1, m.successful_runs
    assert_equal 0, m.failed_runs
    assert_in_delta 1.5, m.total_execution_time, 0.01
  end

  def test_record_pipeline_failure
    error = RuntimeError.new('test error')
    capture_io do
      Monitoring.record_pipeline_failure(error, 2.0)
    end

    m = Monitoring.get_metrics
    assert_equal 1, m.total_runs
    assert_equal 0, m.successful_runs
    assert_equal 1, m.failed_runs
    assert_equal 1, m.errors['RuntimeError']
  end

  def test_get_metrics_no_file
    m = Monitoring.get_metrics
    assert_equal 0, m.total_runs
  end

  def test_get_metrics_corrupted_file
    File.write(@temp_file, 'not valid json{{{')
    m = Monitoring.get_metrics
    assert_equal 0, m.total_runs
  end

  def test_reset_metrics
    capture_io do
      Monitoring.record_pipeline_success(1.0)
    end
    assert File.exist?(@temp_file)

    Monitoring.reset_metrics!
    refute File.exist?(@temp_file)
  end

  def test_print_summary_no_errors
    capture_io do
      Monitoring.record_pipeline_success(1.0)
    end
    out, _err = capture_io { Monitoring.print_summary }
    assert_match(/Pipeline Metrics Summary/, out)
    assert_match(/Total runs:/, out)
    assert_match(/Success rate:/, out)
  end

  def test_print_summary_with_errors
    error = RuntimeError.new('boom')
    capture_io do
      Monitoring.record_pipeline_failure(error, 1.0)
    end
    out, _err = capture_io { Monitoring.print_summary }
    assert_match(/Error breakdown/, out)
    assert_match(/RuntimeError/, out)
  end

  def test_multiple_runs_accumulate
    capture_io do
      Monitoring.record_pipeline_success(1.0)
      Monitoring.record_pipeline_success(2.0)
      Monitoring.record_pipeline_failure(RuntimeError.new('x'), 3.0)
    end

    m = Monitoring.get_metrics
    assert_equal 3, m.total_runs
    assert_equal 2, m.successful_runs
    assert_equal 1, m.failed_runs
    assert_in_delta 6.0, m.total_execution_time, 0.01
  end
end
