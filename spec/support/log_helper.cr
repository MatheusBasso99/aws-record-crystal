require "log"

# Captures what the record layer logs while the block runs.
#
# The Ruby specs assert on a logger double; here a memory backend is attached to the `"aws.record"`
# source for the duration of the block.
def capture_record_logs(& : ->) : Array(String)
  backend = ::Log::MemoryBackend.new
  ::Log.setup do |config|
    config.bind("aws.record", :debug, backend)
  end
  begin
    yield
  ensure
    ::Log.setup_from_env
  end
  backend.entries.map(&.message)
end
