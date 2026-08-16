# Runs the Crystal compiler over a fixture that must not compile, and returns what it said.
#
# The attribute macros catch modelling mistakes — duplicate names, reserved names, storage name
# collisions, an attribute that is both hash and range key — before the program runs, where the Ruby
# gem raises at class definition time. These helpers are how those errors are asserted.
module CompileErrors
  extend self

  # Where the fixtures live.
  DIRECTORY = File.expand_path("../fixtures/compile_errors", __DIR__)

  # Compiles *fixture* and returns the compiler's output, failing the example if it compiled.
  def message_for(fixture : String) : String
    output = IO::Memory.new
    status = Process.run(
      "crystal",
      ["build", "--no-codegen", File.join(DIRECTORY, fixture)],
      output: output, error: output
    )
    raise "Expected #{fixture} not to compile, but it did" if status.success?
    output.to_s
  end
end

# Asserts that *fixture* fails to compile with a message containing *expected*.
def expect_compile_error(fixture : String, expected : String) : Nil
  CompileErrors.message_for(fixture).should contain(expected)
end
