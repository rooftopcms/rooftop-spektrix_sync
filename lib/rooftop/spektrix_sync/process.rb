module Process
  def exists?(pid)
    Process.kill(0, pid)
    true
  rescue => e
    false
  end

  def create_pid(path)
    Pathname(path).write(Process.pid)
  end

  def get_pid(path)
    File.read(path).to_i
  rescue Errno::ENOENT
    false
  end

  def remove_pidfile(path)
    File.delete(path)
  rescue Errno::ENOENT
    false
  end

  module_function :exists?, :create_pid, :get_pid, :remove_pidfile
end