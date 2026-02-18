# frozen_string_literal: true

require_relative 'test_helper'

class TestUtils < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir('utils_test')
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  # --- prepare_directory ---
  def test_prepare_directory_creates_new
    path = File.join(@temp_dir, 'new_dir')
    capture_io { Utils.prepare_directory(path) }
    assert Dir.exist?(path)
  end

  def test_prepare_directory_removes_existing
    path = File.join(@temp_dir, 'existing_dir')
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'old_file.txt'), 'old content')

    capture_io { Utils.prepare_directory(path) }

    assert Dir.exist?(path)
    refute File.exist?(File.join(path, 'old_file.txt'))
  end

  # --- create_and_enter_directory ---
  def test_create_and_enter_directory
    path = File.join(@temp_dir, 'enter_dir')
    original_dir = Dir.pwd

    capture_io { Utils.create_and_enter_directory(path) }

    assert Dir.exist?(path)
    assert_equal path, Dir.pwd
  ensure
    Dir.chdir(original_dir)
  end

  # --- change_directory ---
  def test_change_directory_success
    path = File.join(@temp_dir, 'cd_dir')
    FileUtils.mkdir_p(path)
    original_dir = Dir.pwd

    capture_io { Utils.change_directory(path) }
    assert_equal path, Dir.pwd
  ensure
    Dir.chdir(original_dir)
  end

  def test_change_directory_nonexistent
    path = File.join(@temp_dir, 'nonexistent')

    assert_raises(ArgumentError) do
      capture_io { Utils.change_directory(path) }
    end
  end

  # --- clean_directory ---
  def test_clean_directory_existing
    path = File.join(@temp_dir, 'clean_me')
    FileUtils.mkdir_p(path)

    result = nil
    capture_io { result = Utils.clean_directory(path) }

    assert_equal true, result
    refute Dir.exist?(path)
  end

  def test_clean_directory_nonexistent
    path = File.join(@temp_dir, 'no_such_dir')

    result = nil
    capture_io { result = Utils.clean_directory(path) }

    assert_equal true, result
  end

  # --- safe_execute ---
  def test_safe_execute_success_no_capture
    result = nil
    capture_io { result = Utils.safe_execute('true') }
    assert result[:success]
    assert_equal 0, result[:exit_code]
  end

  def test_safe_execute_failure_no_capture
    result = nil
    capture_io { result = Utils.safe_execute('false') }
    refute result[:success]
  end

  def test_safe_execute_with_capture
    result = nil
    capture_io { result = Utils.safe_execute('echo hello_world', capture_output: true) }
    assert result[:success]
    assert_match(/hello_world/, result[:output])
    assert_equal 0, result[:exit_code]
  end

  def test_safe_execute_failure_with_capture
    result = nil
    capture_io { result = Utils.safe_execute('false', capture_output: true) }
    refute result[:success]
    assert_equal 1, result[:exit_code]
  end

  # --- command_exists? ---
  def test_command_exists_true
    assert Utils.command_exists?('ls')
  end

  def test_command_exists_false
    refute Utils.command_exists?('this_command_surely_does_not_exist_xyz')
  end

  # --- directory_size ---
  def test_directory_size
    path = File.join(@temp_dir, 'sized_dir')
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'a.txt'), 'hello') # 5 bytes

    size = nil
    capture_io { size = Utils.directory_size(path) }
    assert_equal 5, size
  end

  def test_directory_size_nonexistent
    size = nil
    capture_io { size = Utils.directory_size('/nonexistent_dir_xyz') }
    assert_equal 0, size
  end

  # --- format_bytes ---
  def test_format_bytes_zero
    assert_equal '0 B', Utils.format_bytes(0)
  end

  def test_format_bytes_bytes
    assert_equal '500.00 B', Utils.format_bytes(500)
  end

  def test_format_bytes_kilobytes
    assert_match(/KB/, Utils.format_bytes(2048))
  end

  def test_format_bytes_megabytes
    assert_match(/MB/, Utils.format_bytes(5 * 1024 * 1024))
  end

  def test_format_bytes_gigabytes
    assert_match(/GB/, Utils.format_bytes(3 * 1024 * 1024 * 1024))
  end

  # --- sanitize_filename ---
  def test_sanitize_filename_clean
    assert_equal 'hello-world.txt', Utils.sanitize_filename('hello-world.txt')
  end

  def test_sanitize_filename_with_special_chars
    result = Utils.sanitize_filename("my file@#{$.}txt")
    refute_match(/[@#\$ ]/, result)
    assert_match(/my_file/, result)
  end

  def test_sanitize_filename_collapses_underscores
    result = Utils.sanitize_filename('a___b')
    assert_equal 'a_b', result
  end

  def test_sanitize_filename_strips_leading_trailing_underscores
    result = Utils.sanitize_filename('_hello_')
    assert_equal 'hello', result
  end

  # --- error rescue paths ---
  def test_prepare_directory_error
    # Trigger rescue in prepare_directory by using a path under /proc (read-only)
    assert_raises(Errno::ENOENT, Errno::EACCES) do
      capture_io { Utils.prepare_directory('/proc/fake_test_dir/subdir') }
    end
  end

  def test_create_and_enter_directory_error
    original_dir = Dir.pwd
    assert_raises(Errno::ENOENT, Errno::EACCES) do
      capture_io { Utils.create_and_enter_directory('/proc/fake_test_dir/sub') }
    end
  ensure
    Dir.chdir(original_dir)
  end

  def test_directory_size_error
    # Provide a path that exists but causes Find error
    size = nil
    capture_io { size = Utils.directory_size('/proc/1/root') }
    # Either returns a number or 0 on error
    assert_kind_of Integer, size
  end
end
